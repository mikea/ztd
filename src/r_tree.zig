// R-Tree implementation
// Reference: Guttman, R-trees: A dynamic index structure for spatial searching
//
const std = @import("std");
const geom = @import("geom.zig");
const SparseSet = @import("sparse_set.zig").SparseSet;

const Vec = geom.Vec;
const Rect = geom.Rect;
const inf = std.math.inf_f32;
const assert = std.debug.assert;

pub fn RTree(comptime Id: type, comptime maxId: Id, comptime leafSize: usize, comptime middleSize: usize) type {
    const Node = struct {
        const This = @This();

        const Loc = struct {
            node: *This,
            // todo: this u16 can be smaller if leafSize is small.
            i: u16,
        };

        // id -> leaf and index within that contains given id.
        const Locs = SparseSet(Id, maxId, Loc);

        parent: ?Loc = null,
        len: usize = 0,
        rects: []Rect,
        items: union(enum) {
            ids: []Id,
            children: []*This,
        },

        // T is either Id for leaves or *This for middle nodes
        fn init(allocator: std.mem.Allocator, comptime T: type, items: []const T, rects: []const Rect) !*This {
            var node = try allocator.create(This);
            switch (T) {
                Id => {
                    node.* = .{ .len = items.len, .rects = try allocator.alloc(Rect, leafSize + 1), .items = .{ .ids = try allocator.alloc(Id, leafSize + 1) } };
                    std.mem.copy(Id, node.items.ids, items);
                    std.mem.copy(Rect, node.rects, rects);
                },
                *This => {
                    node.* = .{ .len = items.len, .rects = try allocator.alloc(Rect, middleSize + 1), .items = .{ .children = try allocator.alloc(*This, middleSize + 1) } };
                    std.mem.copy(*This, node.items.children, items);
                    std.mem.copy(Rect, node.rects, rects);
                    for (items) |*item, i| {
                        item.*.parent = .{ .node = node, .i = @intCast(u16, i) };
                    }
                },
                else => unreachable,
            }

            return node;
        }

        fn deinit(self: *This, allocator: std.mem.Allocator) void {
            switch (self.items) {
                .ids => |ids| allocator.free(ids),
                .children => |children| {
                    for (children[0..self.len]) |child| {
                        child.deinit(allocator);
                    }
                    allocator.free(children);
                },
            }
            allocator.free(self.rects);
            allocator.destroy(self);
        }

        // T is either Id for leaves or *This for middle nodes
        fn add(self: *This, comptime T: type, idOrChild: T, rect: Rect) void {
            switch (T) {
                Id => {
                    self.items.ids[self.len] = idOrChild;
                },
                *This => {
                    self.items.children[self.len] = idOrChild;
                    idOrChild.parent = .{ .node = self, .i = @intCast(u16, self.len) };
                },
                else => unreachable,
            }

            self.rects[self.len] = rect;
            self.len += 1;
        }

        fn adjustTree(startNode: *This, rect: Rect) void {
            var n = startNode;
            while (n.parent) |parent| {
                parent.node.rects[parent.i] = parent.node.rects[parent.i].add(rect);
                n = parent.node;
            }
        }

        fn bounds(self: *const This) Rect {
            return self.parent.?.node.rects[self.parent.?.i];
        }

        fn deleteEntry(self: *This, idx: usize, locs: *Locs) !void {
            locs.delete(self.items.ids[idx]);

            const last = self.len - 1;
            if (idx < last) {
                const id = self.items.ids[last];
                self.items.ids[idx] = id;
                self.rects[idx] = self.rects[last];
                try locs.set(id, .{ .node = self, .i = @intCast(u16, idx) });
            }

            self.len -= 1;
        }

        fn deleteChild(self: *This, idx: usize, allocator: std.mem.Allocator) void {
            self.items.children[idx].deinit(allocator);

            const last = self.len - 1;
            if (idx < last) {
                self.items.children[idx] = self.items.children[last];
                self.rects[idx] = self.rects[last];
            }
            self.len -= 1;
            if (self.len == 0) {
                @panic("empty middle");
            }
        }

        pub fn format(
            self: *const @This(),
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            switch (self.items) {
                .ids => |ids| try writer.print("Leaf[rects={s}, ids={d}]", .{ self.rects[0..self.len], ids[0..self.len] }),
                .children => |children| {
                    try writer.print("Middle[rects={s}, children={s}]", .{ self.rects[0..self.len], children[0..self.len] });
                },
            }
        }

        pub fn checkConsistency(self: *const @This()) void {
            switch (self.items) {
                .leaf => |*entries| {
                    for (entries[0..self.len]) |entry| {
                        if (!self.rect.containsRect(entry.rect)) {
                            std.log.err("inconsistent leaf entry: {} {}", .{ self.rect, entry });
                            @panic("inconsistent tree");
                        }
                    }
                },
                .middle => |children| {
                    for (children[0..self.len]) |child| {
                        if (!self.rect.containsRect(child.rect)) {
                            @panic("inconsistent tree");
                        }
                        child.checkConsistency();
                    }
                },
            }
        }

        pub fn findIntersect(self: *const @This(), rect: Rect, comptime CallbackThis: type, callbackThis: *CallbackThis, comptime callback: fn (that: *CallbackThis, id: Id, rect: Rect) error{OutOfMemory}!void) !void {
            switch (self.items) {
                .ids => |ids| for (self.rects[0..self.len]) |r, i| {
                    if (r.intersects(rect)) {
                        try callback(callbackThis, ids[i], r);
                    }
                },
                .children => |children| for (self.rects[0..self.len]) |r, i| {
                    if (r.intersects(rect)) {
                        try children[i].findIntersect(rect, CallbackThis, callbackThis, callback);
                    }
                },
            }
        }

        pub fn findPoint(self: *const @This(), p: Vec, comptime CallbackThis: type, callbackThis: *CallbackThis, comptime callback: fn (that: *CallbackThis, id: Id, rect: Rect) error{OutOfMemory}!void) !void {
            switch (self.items) {
                .ids => |ids| for (self.rects[0..self.len]) |rect, i| {
                    if (rect.containsVec(p)) {
                        try callback(callbackThis, ids[i], rect);
                    }
                },
                .children => |children| for (self.rects[0..self.len]) |rect, i| {
                    if (rect.containsVec(p)) {
                        try children[i].findPoint(p, CallbackThis, callbackThis, callback);
                    }
                },
            }
        }
    };

    return struct {
        allocator: std.mem.Allocator,
        root: *Node,
        locs: Node.Locs,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            const root = try Node.init(allocator, Id, &[_]Id{}, &[_]Rect{});
            return .{ .allocator = allocator, .root = root, .locs = try Node.Locs.init(allocator) };
        }

        pub fn deinit(self: *@This()) void {
            self.root.deinit(self.allocator);
            self.locs.deinit();
        }

        fn chooseLeaf(self: *@This(), rect: Rect) *Node {
            var node = self.root;
            while (true) {
                switch (node.items) {
                    .ids => return node,
                    .children => |children| node = children[chooseBestNode(node.rects[0..node.len], rect)],
                }
            }
        }

        pub fn insert(self: *@This(), id: Id, rect: Rect) !void {
            const leafNode = self.chooseLeaf(rect);
            std.debug.assert(leafNode.len <= leafSize);

            leafNode.add(Id, id, rect);
            try self.locs.set(id, .{ .node = leafNode, .i = @intCast(u16, leafNode.len - 1) });
            Node.adjustTree(leafNode, rect);

            if (leafNode.len == leafSize + 1) {
                try self.splitNode(Id, leafNode);
            } else {
                std.debug.assert(leafNode.len <= leafSize);
            }
        }

        fn splitNode(self: *@This(), comptime T: type, node: *Node) error{OutOfMemory}!void {
            var allRects = node.rects;
            var items = if (T == Id) node.items.ids else node.items.children;
            std.debug.assert(allRects.len == items.len);
            std.debug.assert(allRects.len == node.len);

            // QS1 pick first entry for each group
            const seeds = linearPickSeeds(allRects);
            var result = [2]*Node{
                try Node.init(self.allocator, T, &[_]T{items[seeds[0]]}, &[_]Rect{allRects[seeds[0]]}),
                try Node.init(self.allocator, T, &[_]T{items[seeds[1]]}, &[_]Rect{allRects[seeds[1]]}),
            };

            var seedRects = [_]Rect{ allRects[seeds[0]], allRects[seeds[1]] };
            var resultRects = [_]Rect{ allRects[seeds[0]], allRects[seeds[1]] };

            // add the rest
            for (items) |item, i| {
                if (i == seeds[0] or i == seeds[1]) {
                    continue;
                }
                const itemRect = allRects[i];
                // need to compare to original rect to handle well the case when bounds are in a line.
                if (seedRects[0].add(itemRect).area() < seedRects[1].add(itemRect).area()) {
                    result[0].add(T, item, itemRect);
                    resultRects[0] = resultRects[0].add(itemRect);
                } else {
                    result[1].add(T, item, itemRect);
                    resultRects[1] = resultRects[1].add(itemRect);
                }
            }

            // update locs
            if (T == Id) {
                for (result) |n| {
                    for (n.items.ids[0..n.len]) |id, i| {
                        try self.locs.set(id, .{ .node = n, .i = @intCast(u16, i) });
                    }
                }
            }

            if (T == Id) {
                std.debug.assert(result[0].len <= leafSize);
                std.debug.assert(result[1].len <= leafSize);
            } else {
                std.debug.assert(result[0].len <= middleSize);
                std.debug.assert(result[1].len <= middleSize);
            }

            try self.replaceSplitChild(node.parent, node, result, resultRects);
        }

        fn replaceSplitChild(self: *@This(), maybeParent: ?Node.Loc, child: *Node, split: [2]*Node, rects: [2]Rect) !void {
            child.len = 0;
            defer child.deinit(self.allocator);

            if (maybeParent == null) {
                // splitting the root
                assert(child == self.root);
                self.root = try Node.init(self.allocator, *Node, &split, &rects);
                return;
            }

            var parent = maybeParent.?.node;
            for (parent.items.children[0..parent.len]) |ch, i| { // todo
                if (ch == child) {
                    parent.items.children[i] = split[0];
                    parent.rects[i] = rects[0];
                    split[0].parent = .{ .node = parent, .i = @intCast(u16, i) };
                    break;
                }
            }

            parent.items.children[parent.len] = split[1];
            parent.rects[parent.len] = rects[1];
            split[1].parent = .{ .node = parent, .i = @intCast(u16, parent.len) };
            parent.len += 1;
            if (parent.len == parent.rects.len) {
                try self.splitNode(*Node, parent);
            }
        }

        pub fn findIntersect(self: *const @This(), rect: Rect, comptime CallbackThis: type, callbackThis: *CallbackThis, comptime callback: fn (that: *CallbackThis, id: Id, rect: Rect) error{OutOfMemory}!void) !void {
            try self.root.findIntersect(rect, CallbackThis, callbackThis, callback);
        }

        pub fn findPoint(self: *const @This(), p: Vec, comptime CallbackThis: type, callbackThis: *CallbackThis, comptime callback: fn (that: *CallbackThis, id: Id, rect: Rect) error{OutOfMemory}!void) !void {
            try self.root.findPoint(p, CallbackThis, callbackThis, callback);
        }

        pub fn delete(self: *@This(), id: Id) !void {
            try self.deleteLoc(self.find(id));
        }

        pub fn update(self: *@This(), id: Id, newRect: Rect) !void {
            const loc = self.find(id);
            std.debug.assert(loc.node.items.ids[loc.i] == id);
            if (loc.node.bounds().containsRect(newRect)) {
                loc.node.rects[loc.i] = newRect;
            } else {
                try self.deleteLoc(loc);
                try self.insert(id, newRect);
            }
        }

        fn deleteLoc(self: *@This(), loc: Node.Loc) !void {
            try loc.node.deleteEntry(loc.i, &self.locs);
            // if (loc.node.len == 0) {
            //     const p = loc.node.parent.?;
            //     p.node.deleteChild(p.i, self.allocator);
            // }
        }

        fn find(self: *@This(), id: Id) Node.Loc {
            return self.locs.get(id).*;
        }

        pub fn checkConsistency(self: *@This()) void {
            self.root.checkConsistency();
        }

        pub fn format(
            self: *const @This(),
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.print("RTree[root={}]", .{self.root});
        }
    };
}

// chooses a rect that will gain the least area if extended to include
// given rect.
fn chooseBestNode(rects: []const Rect, rect: Rect) usize {
    var result: usize = 0;
    var minIncrease: f32 = std.math.inf_f32;

    for (rects) |r, i| {
        const nodeArea = r.area();
        const newArea = r.add(rect).area();

        if ((newArea - nodeArea) < minIncrease) {
            minIncrease = newArea - nodeArea;
            result = i;
        }
    }

    return result;
}

fn linearPickSeeds(rects: []Rect) [2]usize {
    // LPS1 Find extreme rectangles along all dimensions
    const first = rects[0];
    const last = rects[rects.len - 1];

    var lowestX = first.a.x;
    var lowestY = first.a.y;
    var highestX = first.b.x;
    var highestY = first.b.y;

    var highestLowX = first.a.x;
    var highestLowXIdx: usize = 0;
    var lowestHighX = last.b.x;
    var lowestHighXIdx: usize = rects.len - 1;

    var highestLowY = first.a.y;
    var highestLowYIdx: usize = 0;
    var lowestHighY = last.b.y;
    var lowestHighYIdx: usize = rects.len - 1;

    for (rects) |rect, i| {
        lowestX = std.math.min(lowestX, rect.a.x);
        lowestY = std.math.min(lowestY, rect.a.y);

        highestX = std.math.max(highestX, rect.b.x);
        highestY = std.math.max(highestY, rect.b.y);

        if (rect.a.x > highestLowX and i != lowestHighXIdx) {
            highestLowX = rect.a.x;
            highestLowXIdx = i;
        }
        if (rect.a.y > highestLowY and i != lowestHighYIdx) {
            highestLowY = rect.a.y;
            highestLowYIdx = i;
        }

        if (rect.b.x < lowestHighX and i != highestLowXIdx) {
            lowestHighX = rect.b.x;
            lowestHighXIdx = i;
        }
        if (rect.b.y < lowestHighY and i != highestLowYIdx) {
            lowestHighY = rect.b.y;
            lowestHighYIdx = i;
        }
    }

    const separationX = std.math.fabs(lowestHighX - highestLowX);
    const separationY = std.math.fabs(lowestHighY - highestLowY);

    // LPS2 Adjust for shape of the rectangle cluster
    const normSeparationX = separationX / (highestX - lowestX);
    const normSeparationY = separationY / (highestY - lowestY);

    if (normSeparationX > normSeparationY) {
        std.debug.assert(lowestHighXIdx != highestLowXIdx);
        return [_]usize{ lowestHighXIdx, highestLowXIdx };
    } else {
        std.debug.assert(lowestHighYIdx != highestLowYIdx);
        return [_]usize{ lowestHighYIdx, highestLowYIdx };
    }
}

// tests

const expect = std.testing.expect;

fn expectFormat(tree: anytype, expected: []const u8) !void {
    const actual = try std.fmt.allocPrint(std.testing.allocator, "{s}", .{tree});
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

test "rtree" {
    var tree = try RTree(u16, 1024, 4, 3).init(std.testing.allocator);
    defer tree.deinit();

    try expectFormat(&tree, "RTree[root=Leaf[rects={  }, ids={  }]]");

    // Start adding from top right:
    //
    // 0                ┌───┐
    //                  │   │
    // 9              ┌─┼─┐ │
    //                │ │ │ │
    // 8            ┌─┼─┼─┼─┘
    //              │ │ │ │
    // 7          ┌─┼─┼─┼─┘
    //            │ │ │ │
    // 6        ┌─┼─┼─┼─┘
    //          │ │ │ │
    // 5      ┌─┼─┼─┼─┘
    //        │ │ │ │
    // 4    ┌─┼─┼─┼─┘
    //      │ │ │ │
    // 3  ┌─┼─┼─┼─┘
    //    │ │ │ │
    // 2┌─┼─┼─┼─┘
    //  │ │ │ │
    // 1│ └─┼─┘
    //  │   │
    // 0└───┘
    //  0 1 2 3 4 5 6 7 8 9 0

    try tree.insert(0, Rect.init(8, 8, 10, 10));
    try expectFormat(&tree, "RTree[root=Leaf[rects={ [(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)] }, ids={ 0 }]]");

    try tree.insert(1, Rect.init(7, 7, 9, 9));
    try expectFormat(&tree, "RTree[root=Leaf[rects={ [(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)], [(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)] }, ids={ 0, 1 }]]");

    try tree.insert(2, Rect.init(6, 6, 8, 8));
    try expectFormat(&tree, "RTree[root=Leaf[rects={ [(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)], [(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)], [(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)] }, ids={ 0, 1, 2 }]]");

    try tree.insert(3, Rect.init(5, 5, 7, 7));
    try expectFormat(&tree, "RTree[root=Leaf[rects={ [(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)], [(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)], [(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)], [(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)] }, ids={ 0, 1, 2, 3 }]]");

    try tree.insert(4, Rect.init(4, 4, 6, 6));
    try expectFormat(&tree, "RTree[root=Middle[rects={ [(4.0e+00,4.0e+00),(7.0e+00,7.0e+00)], [(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)] }, children={ " ++
        "Leaf[rects={ [(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)], [(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)] }, ids={ 4, 3 }], " ++
        "Leaf[rects={ [(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)], [(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)], [(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)] }, ids={ 0, 1, 2 }] }]]");

    try tree.insert(5, Rect.init(3, 3, 5, 5));
    try expectFormat(&tree, "RTree[root=Middle[rects={ [(3.0e+00,3.0e+00),(7.0e+00,7.0e+00)], [(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)] }, children={ " ++
        "Leaf[rects={ [(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)], [(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)], [(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)] }, ids={ 4, 3, 5 }], " ++
        "Leaf[rects={ [(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)], [(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)], [(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)] }, ids={ 0, 1, 2 }] }]]");

    try tree.insert(6, Rect.init(2, 2, 4, 4));
    try expectFormat(&tree, "RTree[root=Middle[rects={ [(2.0e+00,2.0e+00),(7.0e+00,7.0e+00)], [(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)] }, children={ " ++
        "Leaf[rects={ [(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)], [(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)], [(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)], [(2.0e+00,2.0e+00),(4.0e+00,4.0e+00)] }, ids={ 4, 3, 5, 6 }], " ++
        "Leaf[rects={ [(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)], [(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)], [(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)] }, ids={ 0, 1, 2 }] }]]");

    try tree.insert(7, Rect.init(1, 1, 3, 3));
    try expectFormat(&tree, "RTree[root=Middle[rects={ [(1.0e+00,1.0e+00),(4.0e+00,4.0e+00)], [(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], [(3.0e+00,3.0e+00),(7.0e+00,7.0e+00)] }, children={ " ++
        "Leaf[rects={ [(1.0e+00,1.0e+00),(3.0e+00,3.0e+00)], [(2.0e+00,2.0e+00),(4.0e+00,4.0e+00)] }, ids={ 7, 6 }], " ++
        "Leaf[rects={ [(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)], [(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)], [(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)] }, ids={ 0, 1, 2 }], " ++
        "Leaf[rects={ [(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)], [(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)], [(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)] }, ids={ 3, 4, 5 }] }]]");

    try tree.insert(8, Rect.init(0, 0, 2, 2));
    try expectFormat(&tree, "RTree[root=Middle[rects={ [(0.0e+00,0.0e+00),(4.0e+00,4.0e+00)], [(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], [(3.0e+00,3.0e+00),(7.0e+00,7.0e+00)] }, children={ " ++
        "Leaf[rects={ [(1.0e+00,1.0e+00),(3.0e+00,3.0e+00)], [(2.0e+00,2.0e+00),(4.0e+00,4.0e+00)], [(0.0e+00,0.0e+00),(2.0e+00,2.0e+00)] }, ids={ 7, 6, 8 }], " ++
        "Leaf[rects={ [(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)], [(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)], [(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)] }, ids={ 0, 1, 2 }], " ++
        "Leaf[rects={ [(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)], [(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)], [(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)] }, ids={ 3, 4, 5 }] }]]");

    try tree.insert(9, Rect.init(-1, -1, 1, 1));
    try expectFormat(&tree, "RTree[root=Middle[rects={ [(-1.0e+00,-1.0e+00),(4.0e+00,4.0e+00)], [(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], [(3.0e+00,3.0e+00),(7.0e+00,7.0e+00)] }, children={ " ++
        "Leaf[rects={ [(1.0e+00,1.0e+00),(3.0e+00,3.0e+00)], [(2.0e+00,2.0e+00),(4.0e+00,4.0e+00)], [(0.0e+00,0.0e+00),(2.0e+00,2.0e+00)], [(-1.0e+00,-1.0e+00),(1.0e+00,1.0e+00)] }, ids={ 7, 6, 8, 9 }], " ++
        "Leaf[rects={ [(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)], [(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)], [(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)] }, ids={ 0, 1, 2 }], " ++
        "Leaf[rects={ [(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)], [(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)], [(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)] }, ids={ 3, 4, 5 }] }]]");

    try tree.insert(10, Rect.init(-2, -2, 0, 0));
    try expectFormat(&tree, "RTree[root=Middle[rects={ [(-2.0e+00,-2.0e+00),(4.0e+00,4.0e+00)], [(3.0e+00,3.0e+00),(1.0e+01,1.0e+01)] }, children={ " ++
        ("Middle[rects={ [(0.0e+00,0.0e+00),(4.0e+00,4.0e+00)], [(-2.0e+00,-2.0e+00),(1.0e+00,1.0e+00)] }, children={ " ++
        "Leaf[rects={ [(2.0e+00,2.0e+00),(4.0e+00,4.0e+00)], [(1.0e+00,1.0e+00),(3.0e+00,3.0e+00)], [(0.0e+00,0.0e+00),(2.0e+00,2.0e+00)] }, ids={ 6, 7, 8 }], " ++
        "Leaf[rects={ [(-2.0e+00,-2.0e+00),(0.0e+00,0.0e+00)], [(-1.0e+00,-1.0e+00),(1.0e+00,1.0e+00)] }, ids={ 10, 9 }] }], ") ++
        ("Middle[rects={ [(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], [(3.0e+00,3.0e+00),(7.0e+00,7.0e+00)] }, children={ " ++
        "Leaf[rects={ [(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)], [(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)], [(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)] }, ids={ 0, 1, 2 }], " ++
        "Leaf[rects={ [(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)], [(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)], [(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)] }, ids={ 3, 4, 5 }] }]") ++
        " }]]");

    var collector: struct {
        ids: std.ArrayList(u16) = std.ArrayList(u16).init(std.testing.allocator),

        pub fn callback(self: *@This(), id: u16, _: Rect) error{OutOfMemory}!void {
            try self.ids.append(id);
        }

        pub fn deinit(self: *@This()) void {
            self.ids.deinit();
        }
    } = .{};
    defer collector.deinit();

    try tree.findIntersect(Rect.init(0, 0, 2, 2), @TypeOf(collector), &collector, @TypeOf(collector).callback);
    try std.testing.expectEqualSlices(u16, &[_]u16{ 6, 7, 8, 10, 9 }, collector.ids.items);

    collector.ids.clearRetainingCapacity();
    try tree.findPoint(.{ .x = 0, .y = 0 }, @TypeOf(collector), &collector, @TypeOf(collector).callback);
    try std.testing.expectEqualSlices(u16, &[_]u16{ 8, 10, 9 }, collector.ids.items);

    try tree.delete(7);
    try expectFormat(&tree, "RTree[root=Middle[rects={ [(-2.0e+00,-2.0e+00),(4.0e+00,4.0e+00)], [(3.0e+00,3.0e+00),(1.0e+01,1.0e+01)] }, children={ Middle[rects={ [(0.0e+00,0.0e+00),(4.0e+00,4.0e+00)], [(-2.0e+00,-2.0e+00),(1.0e+00,1.0e+00)] }, children={ Leaf[rects={ [(2.0e+00,2.0e+00),(4.0e+00,4.0e+00)], [(0.0e+00,0.0e+00),(2.0e+00,2.0e+00)] }, ids={ 6, 8 }], Leaf[rects={ [(-2.0e+00,-2.0e+00),(0.0e+00,0.0e+00)], [(-1.0e+00,-1.0e+00),(1.0e+00,1.0e+00)] }, ids={ 10, 9 }] }], Middle[rects={ [(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], [(3.0e+00,3.0e+00),(7.0e+00,7.0e+00)] }, children={ Leaf[rects={ [(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)], [(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)], [(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)] }, ids={ 0, 1, 2 }], Leaf[rects={ [(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)], [(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)], [(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)] }, ids={ 3, 4, 5 }] }] }]]");
}
