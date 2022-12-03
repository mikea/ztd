// R-Tree implementation
// Reference: Guttman, R-trees: A dynamic index structure for spatial searching
//
const std = @import("std");
const geom = @import("geom.zig");
const SparseSet = @import("sparse_set.zig").SparseSet;

const Vec = geom.Vec2;
const Rect = geom.Rect;
const inf = std.math.inf_f32;
const assert = std.debug.assert;

var prng = std.rand.DefaultPrng.init(0);
const random = prng.random();

pub fn RTree(comptime Id: type, comptime maxId: Id, comptime leafSize: usize, comptime middleSize: usize) type {
    const Entry = struct {
        id: Id,
        rect: Rect,

        pub fn format(
            self: *const @This(),
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.print("(id={},rect={})", .{ self.id, self.rect });
        }
    };

    const Node = struct {
        const This = @This();
        const Loc = struct {
            node: *This,
            // todo: this u16 can be smaller if leafSize is small.
            i: u16,
        };

        const Locs = SparseSet(Id, maxId, Loc);
        const NodeType = enum { leaf, middle };

        parent: ?*This = null,
        rect: Rect = Rect.init(0, 0, 0, 0),
        len: usize = 0,
        items: union(NodeType) {
            leaf: [leafSize + 1]Entry,
            middle: [middleSize + 1]*This,
        },

        fn init(allocator: std.mem.Allocator, comptime T: type, items: []const T) !*This {
            var node = try allocator.create(This);
            var rect = items[0].rect;

            if (items.len > 1) {
                for (items) |item| {
                    rect = rect.add(item.rect);
                }
            }

            switch (T) {
                Entry => {
                    node.* = .{ .len = 1, .rect = rect, .items = .{ .leaf = undefined } };
                    std.mem.copy(T, &(node.items.leaf), items);
                },
                *This => {
                    node.* = .{ .len = items.len, .rect = rect, .items = .{ .middle = undefined } };
                    std.mem.copy(T, &(node.items.middle), items);
                    for (node.items.middle[0..items.len]) |*item| {
                        item.*.parent = node;
                    }
                },
                else => unreachable,
            }

            return node;
        }

        fn add(self: *This, comptime T: type, entryOrChild: T) void {
            switch (T) {
                Entry => self.items.leaf[self.len] = entryOrChild,
                *This => {
                    self.items.middle[self.len] = entryOrChild;
                    entryOrChild.parent = self;
                },
                else => unreachable,
            }

            self.len += 1;
            if (self.len == 1) {
                self.rect = entryOrChild.rect;
            } else {
                self.rect = self.rect.add(entryOrChild.rect);
            }
        }

        fn delete(self: *This, idx: usize, locs: *Locs) !void {
            try locs.delete(self.items.leaf[idx].id);

            if (idx == self.len - 1) {
                self.len -= 1;
                return;
            }

            self.items.leaf[idx] = self.items.leaf[self.len - 1];
            try locs.set(self.items.leaf[idx].id, .{.node = self, .i = @intCast(u16, idx)});
            self.len -= 1;
        }

        pub fn format(
            self: *const @This(),
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            switch (self.items) {
                .leaf => |entries| try writer.print("Leaf[rect={}, items={s}]", .{ self.rect, entries[0..self.len] }),
                .middle => |children| {
                    try writer.print("Middle[rect={}, children={s}]", .{ self.rect, children[0..self.len] });
                },
            }
        }

        fn chooseLeaf(self: *This, rect: Rect) *This {
            var node = self;
            while (true) {
                switch (node.items) {
                    .leaf => return node,
                    .middle => |*children| node = chooseNode(children[0..node.len], rect),
                }
            }
        }

        // chooses a node that will gain the least area if extended to include
        // given rect.
        fn chooseNode(nodes: []const *This, rect: Rect) *This {
            var result: *This = nodes[0];
            var minIncrease: f32 = std.math.inf_f32;

            for (nodes) |node| {
                const nodeArea = node.rect.area();
                const newArea = node.rect.add(rect).area();

                if ((newArea - nodeArea) < minIncrease) {
                    minIncrease = newArea - nodeArea;
                    result = node;
                }
            }

            return result;
        }

        fn adjustTree(startNode: ?*This, rect: Rect) void {
            var n = startNode;
            while (n) |node| {
                node.rect = node.rect.add(rect);
                n = node.parent;
            }
        }

        pub fn findIntersect(self: *const @This(), rect: Rect, comptime CallbackThis: type, callbackThis: *CallbackThis, comptime callback: fn (that: *CallbackThis, id: Id, rect: Rect) error{OutOfMemory}!void) !void {
            switch (self.items) {
                .leaf => |entries| for (entries[0..self.len]) |entry| {
                    if (entry.rect.intersects(rect)) {
                        try callback(callbackThis, entry.id, entry.rect);
                    }
                },
                .middle => |children| for (children[0..self.len]) |child| {
                    if (child.rect.intersects(rect)) {
                        try child.findIntersect(rect, CallbackThis, callbackThis, callback);
                    }
                },
            }
        }

        pub fn findPoint(self: *const @This(), p: Vec, comptime CallbackThis: type, callbackThis: *CallbackThis, comptime callback: fn (that: *CallbackThis, id: Id, rect: Rect) error{OutOfMemory}!void) !void {
            switch (self.items) {
                .leaf => |entries| for (entries[0..self.len]) |entry| {
                    if (entry.rect.contains(p)) {
                        try callback(callbackThis, entry.id, entry.rect);
                    }
                },
                .middle => |children| for (children[0..self.len]) |child| {
                    if (child.rect.contains(p)) {
                        try child.findPoint(p, CallbackThis, callbackThis, callback);
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
            const root = try allocator.create(Node);
            root.* = .{ .items = .{ .leaf = .{} } };
            return .{ .allocator = allocator, .root = root, .locs = try Node.Locs.init(allocator) };
        }

        pub fn deinit(self: *@This()) void {
            self.destroy(self.root);
            self.locs.deinit();
        }

        fn destroy(self: *@This(), node: *Node) void {
            switch (node.items) {
                .leaf => {},
                .middle => |children| {
                    for (children[0..node.len]) |child| {
                        self.destroy(child);
                    }
                },
            }
            self.allocator.destroy(node);
        }

        pub fn insert(self: *@This(), id: Id, rect: Rect) !void {
            const leafNode = self.root.chooseLeaf(rect);
            std.debug.assert(leafNode.len <= leafSize);

            leafNode.add(Entry, .{ .id = id, .rect = rect });
            try self.locs.set(id, .{ .node = leafNode, .i = @intCast(u16, leafNode.len - 1) });
            Node.adjustTree(leafNode.parent, rect);

            if (leafNode.len == leafNode.items.leaf.len) {
                try self.splitNode(Entry, leafNode);
            } else {
                std.debug.assert(leafNode.len <= leafSize);
            }
        }

        fn splitNode(self: *@This(), comptime T: type, node: *Node) error{OutOfMemory}!void {
            var items = if (T == Entry) node.items.leaf else node.items.middle;
            if (T == Entry) {
                std.debug.assert(items.len == leafSize + 1);
            } else {
                std.debug.assert(items.len == middleSize + 1);
            }

            // QS1 pick first entry for each group
            const seeds = linearPickSeeds(T, &items);
            var result = [2]*Node{
                try Node.init(self.allocator, T, &[_]T{items[seeds[0]]}),
                try Node.init(self.allocator, T, &[_]T{items[seeds[1]]}),
            };

            // need to compare to original rect to handle well the case when bounds are in a line.
            var rects = [_]Rect{ result[0].rect, result[1].rect };

            // add the rest
            for (items) |item, i| {
                if (i == seeds[0] or i == seeds[1]) {
                    continue;
                }
                if (rects[0].add(item.rect).area() < rects[1].add(item.rect).area()) {
                    result[0].add(T, item);
                } else {
                    result[1].add(T, item);
                }
            }

            // update locs
            if (T == Entry) {
                for (result) |n| {
                    for (n.items.leaf[0..n.len]) |*entry, i| {
                        try self.locs.set(entry.id, .{ .node = n, .i = @intCast(u16, i)});
                    }
                }
            }

            if (T == Entry) {
                std.debug.assert(result[0].len <= leafSize);
                std.debug.assert(result[1].len <= leafSize);
            } else {
                std.debug.assert(result[0].len <= middleSize);
                std.debug.assert(result[1].len <= middleSize);
            }

            try self.replaceSplitChild(node.parent, node, result);
        }

        fn replaceSplitChild(self: *@This(), maybeParent: ?*Node, child: *Node, split: [2]*Node) !void {
            defer self.allocator.destroy(child);

            if (maybeParent == null) {
                // splitting the root
                assert(child == self.root);
                self.root = try Node.init(self.allocator, *Node, &split);
                return;
            }

            var parent = maybeParent.?;
            for (parent.items.middle[0..parent.len]) |ch, i| {
                if (ch == child) {
                    parent.items.middle[i] = split[0];
                    break;
                }
            }

            parent.items.middle[parent.len] = split[1];
            parent.len += 1;
            split[0].parent = parent;
            split[1].parent = parent;
            if (parent.len == parent.items.middle.len) {
                try self.splitNode(*Node, parent);
            }
        }

        pub fn findIntersect(self: *const @This(), rect: Rect, comptime CallbackThis: type, callbackThis: *CallbackThis, comptime callback: fn (that: *CallbackThis, id: Id, rect: Rect) error{OutOfMemory}!void) !void {
            if (!self.root.rect.intersects(rect)) {
                return;
            }
            try self.root.findIntersect(rect, CallbackThis, callbackThis, callback);
        }


        pub fn findPoint(self: *const @This(), p: Vec, comptime CallbackThis: type, callbackThis: *CallbackThis, comptime callback: fn (that: *CallbackThis, id: Id, rect: Rect) error{OutOfMemory}!void) !void {
            if (!self.root.rect.contains(p)) {
                return;
            }
            try self.root.findPoint(p, CallbackThis, callbackThis, callback);
        }

        pub fn delete(self: *@This(), id: Id) !void {
            const loc = try self.find(id);
            try loc.node.delete(loc.i, &self.locs);
        }

        pub fn update(self: *@This(), id: Id, newRect: Rect) !void {
            const loc = try self.find(id);
            const entry = &loc.node.items.leaf[loc.i];

            if (loc.node.rect.add(newRect).area() == loc.node.rect.area()) {
                entry.rect = newRect;
            } else {
                try loc.node.delete(loc.i, &self.locs);
                try self.insert(id, newRect);
            }
        }

        fn find(self: *@This(), id: Id) !*Node.Loc {
            const loc = try self.locs.get(id);
            // std.debug.assert(loc.i < loc.node.len);
            // std.debug.assert(loc.node.items.leaf[loc.i].id == id);
            return loc;
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

fn linearPickSeeds(comptime T: type, entries: []T) [2]usize {
    // LPS1 Find extreme rectangles along all dimensions
    const first = entries[0].rect;
    const last = entries[entries.len - 1].rect;

    var lowestX = first.a.x;
    var lowestY = first.a.y;
    var highestX = first.b.x;
    var highestY = first.b.y;

    var highestLowX = first.a.x;
    var highestLowXIdx: usize = 0;
    var lowestHighX = last.b.x;
    var lowestHighXIdx: usize = entries.len - 1;

    var highestLowY = first.a.y;
    var highestLowYIdx: usize = 0;
    var lowestHighY = last.b.y;
    var lowestHighYIdx: usize = entries.len - 1;

    for (entries) |entry, i| {
        lowestX = std.math.min(lowestX, entry.rect.a.x);
        lowestY = std.math.min(lowestY, entry.rect.a.y);

        highestX = std.math.max(highestX, entry.rect.b.x);
        highestY = std.math.max(highestY, entry.rect.b.y);

        if (entry.rect.a.x > highestLowX and i != lowestHighXIdx) {
            highestLowX = entry.rect.a.x;
            highestLowXIdx = i;
        }
        if (entry.rect.a.y > highestLowY and i != lowestHighYIdx) {
            highestLowY = entry.rect.a.y;
            highestLowYIdx = i;
        }

        if (entry.rect.b.x < lowestHighX and i != highestLowXIdx) {
            lowestHighX = entry.rect.b.x;
            lowestHighXIdx = i;
        }
        if (entry.rect.b.y < lowestHighY and i != highestLowYIdx) {
            lowestHighY = entry.rect.b.y;
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

fn shuffleArray(comptime T: type, arr: []T) void {
    var i = arr.len - 1;
    while (i > 0) {
        const j = random.int(usize) % (i + 1);
        var x = arr[i];
        arr[i] = arr[j];
        arr[j] = x;

        i -= 1;
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

    try expectFormat(&tree, "RTree[root=Leaf[rect=[(0.0e+00,0.0e+00),(0.0e+00,0.0e+00)], items={  }]]");

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
    try expectFormat(&tree, "RTree[root=Leaf[rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)], items={ (id=0,rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)]) }]]");

    try tree.insert(1, Rect.init(7, 7, 9, 9));
    try expectFormat(&tree, "RTree[root=Leaf[rect=[(7.0e+00,7.0e+00),(1.0e+01,1.0e+01)], items={ (id=0,rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)]), (id=1,rect=[(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)]) }]]");

    try tree.insert(2, Rect.init(6, 6, 8, 8));
    try expectFormat(&tree, "RTree[root=Leaf[rect=[(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], items={ (id=0,rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)]), (id=1,rect=[(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)]), (id=2,rect=[(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)]) }]]");

    try tree.insert(3, Rect.init(5, 5, 7, 7));
    try expectFormat(&tree, "RTree[root=Leaf[rect=[(5.0e+00,5.0e+00),(1.0e+01,1.0e+01)], items={ (id=0,rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)]), (id=1,rect=[(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)]), (id=2,rect=[(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)]), (id=3,rect=[(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)]) }]]");

    try tree.insert(4, Rect.init(4, 4, 6, 6));
    try expectFormat(&tree, "RTree[root=Middle[rect=[(4.0e+00,4.0e+00),(1.0e+01,1.0e+01)], children={ Leaf[rect=[(4.0e+00,4.0e+00),(7.0e+00,7.0e+00)], items={ (id=4,rect=[(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)]), (id=3,rect=[(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)]) }], Leaf[rect=[(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], items={ (id=0,rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)]), (id=1,rect=[(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)]), (id=2,rect=[(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)]) }] }]]");

    try tree.insert(5, Rect.init(3, 3, 5, 5));
    try expectFormat(&tree, "RTree[root=Middle[rect=[(3.0e+00,3.0e+00),(1.0e+01,1.0e+01)], children={ Leaf[rect=[(3.0e+00,3.0e+00),(7.0e+00,7.0e+00)], items={ (id=4,rect=[(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)]), (id=3,rect=[(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)]), (id=5,rect=[(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)]) }], Leaf[rect=[(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], items={ (id=0,rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)]), (id=1,rect=[(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)]), (id=2,rect=[(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)]) }] }]]");

    try tree.insert(6, Rect.init(2, 2, 4, 4));
    try expectFormat(&tree, "RTree[root=Middle[rect=[(2.0e+00,2.0e+00),(1.0e+01,1.0e+01)], children={ Leaf[rect=[(2.0e+00,2.0e+00),(7.0e+00,7.0e+00)], items={ (id=4,rect=[(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)]), (id=3,rect=[(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)]), (id=5,rect=[(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)]), (id=6,rect=[(2.0e+00,2.0e+00),(4.0e+00,4.0e+00)]) }], Leaf[rect=[(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], items={ (id=0,rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)]), (id=1,rect=[(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)]), (id=2,rect=[(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)]) }] }]]");

    try tree.insert(7, Rect.init(1, 1, 3, 3));
    try expectFormat(&tree, "RTree[root=Middle[rect=[(1.0e+00,1.0e+00),(1.0e+01,1.0e+01)], children={ Leaf[rect=[(1.0e+00,1.0e+00),(4.0e+00,4.0e+00)], items={ (id=7,rect=[(1.0e+00,1.0e+00),(3.0e+00,3.0e+00)]), (id=6,rect=[(2.0e+00,2.0e+00),(4.0e+00,4.0e+00)]) }], Leaf[rect=[(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], items={ (id=0,rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)]), (id=1,rect=[(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)]), (id=2,rect=[(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)]) }], Leaf[rect=[(3.0e+00,3.0e+00),(7.0e+00,7.0e+00)], items={ (id=3,rect=[(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)]), (id=4,rect=[(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)]), (id=5,rect=[(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)]) }] }]]");

    try tree.insert(8, Rect.init(0, 0, 2, 2));
    try expectFormat(&tree, "RTree[root=Middle[rect=[(0.0e+00,0.0e+00),(1.0e+01,1.0e+01)], children={ Leaf[rect=[(0.0e+00,0.0e+00),(4.0e+00,4.0e+00)], items={ (id=7,rect=[(1.0e+00,1.0e+00),(3.0e+00,3.0e+00)]), (id=6,rect=[(2.0e+00,2.0e+00),(4.0e+00,4.0e+00)]), (id=8,rect=[(0.0e+00,0.0e+00),(2.0e+00,2.0e+00)]) }], Leaf[rect=[(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], items={ (id=0,rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)]), (id=1,rect=[(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)]), (id=2,rect=[(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)]) }], Leaf[rect=[(3.0e+00,3.0e+00),(7.0e+00,7.0e+00)], items={ (id=3,rect=[(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)]), (id=4,rect=[(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)]), (id=5,rect=[(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)]) }] }]]");

    try tree.insert(9, Rect.init(-1, -1, 1, 1));
    try expectFormat(&tree, "RTree[root=Middle[rect=[(-1.0e+00,-1.0e+00),(1.0e+01,1.0e+01)], children={ Leaf[rect=[(-1.0e+00,-1.0e+00),(4.0e+00,4.0e+00)], items={ (id=7,rect=[(1.0e+00,1.0e+00),(3.0e+00,3.0e+00)]), (id=6,rect=[(2.0e+00,2.0e+00),(4.0e+00,4.0e+00)]), (id=8,rect=[(0.0e+00,0.0e+00),(2.0e+00,2.0e+00)]), (id=9,rect=[(-1.0e+00,-1.0e+00),(1.0e+00,1.0e+00)]) }], Leaf[rect=[(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], items={ (id=0,rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)]), (id=1,rect=[(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)]), (id=2,rect=[(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)]) }], Leaf[rect=[(3.0e+00,3.0e+00),(7.0e+00,7.0e+00)], items={ (id=3,rect=[(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)]), (id=4,rect=[(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)]), (id=5,rect=[(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)]) }] }]]");

    try tree.insert(10, Rect.init(-2, -2, 0, 0));
    try expectFormat(&tree, "RTree[root=Middle[rect=[(-2.0e+00,-2.0e+00),(1.0e+01,1.0e+01)], children={ " ++
        "Middle[rect=[(-2.0e+00,-2.0e+00),(4.0e+00,4.0e+00)], children={ " ++
        "Leaf[rect=[(0.0e+00,0.0e+00),(4.0e+00,4.0e+00)], items={ (id=6,rect=[(2.0e+00,2.0e+00),(4.0e+00,4.0e+00)]), (id=7,rect=[(1.0e+00,1.0e+00),(3.0e+00,3.0e+00)]), (id=8,rect=[(0.0e+00,0.0e+00),(2.0e+00,2.0e+00)]) }], " ++
        "Leaf[rect=[(-2.0e+00,-2.0e+00),(1.0e+00,1.0e+00)], items={ (id=10,rect=[(-2.0e+00,-2.0e+00),(0.0e+00,0.0e+00)]), (id=9,rect=[(-1.0e+00,-1.0e+00),(1.0e+00,1.0e+00)]) }] " ++
        "}], " ++
        "Middle[rect=[(3.0e+00,3.0e+00),(1.0e+01,1.0e+01)], children={ " ++
        "Leaf[rect=[(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], items={ (id=0,rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)]), (id=1,rect=[(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)]), (id=2,rect=[(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)]) }], " ++
        "Leaf[rect=[(3.0e+00,3.0e+00),(7.0e+00,7.0e+00)], items={ (id=3,rect=[(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)]), (id=4,rect=[(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)]), (id=5,rect=[(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)]) }] " ++
        "}] " ++
        "}]]");

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

    try tree.delete(7);
    try expectFormat(&tree, "RTree[root=Middle[rect=[(-2.0e+00,-2.0e+00),(1.0e+01,1.0e+01)], children={ " ++
        "Middle[rect=[(-2.0e+00,-2.0e+00),(4.0e+00,4.0e+00)], children={ " ++
        "Leaf[rect=[(0.0e+00,0.0e+00),(4.0e+00,4.0e+00)], items={ (id=6,rect=[(2.0e+00,2.0e+00),(4.0e+00,4.0e+00)]), (id=8,rect=[(0.0e+00,0.0e+00),(2.0e+00,2.0e+00)]) }], " ++
        "Leaf[rect=[(-2.0e+00,-2.0e+00),(1.0e+00,1.0e+00)], items={ (id=10,rect=[(-2.0e+00,-2.0e+00),(0.0e+00,0.0e+00)]), (id=9,rect=[(-1.0e+00,-1.0e+00),(1.0e+00,1.0e+00)]) }] " ++
        "}], " ++
        "Middle[rect=[(3.0e+00,3.0e+00),(1.0e+01,1.0e+01)], children={ " ++
        "Leaf[rect=[(6.0e+00,6.0e+00),(1.0e+01,1.0e+01)], items={ (id=0,rect=[(8.0e+00,8.0e+00),(1.0e+01,1.0e+01)]), (id=1,rect=[(7.0e+00,7.0e+00),(9.0e+00,9.0e+00)]), (id=2,rect=[(6.0e+00,6.0e+00),(8.0e+00,8.0e+00)]) }], " ++
        "Leaf[rect=[(3.0e+00,3.0e+00),(7.0e+00,7.0e+00)], items={ (id=3,rect=[(5.0e+00,5.0e+00),(7.0e+00,7.0e+00)]), (id=4,rect=[(4.0e+00,4.0e+00),(6.0e+00,6.0e+00)]), (id=5,rect=[(3.0e+00,3.0e+00),(5.0e+00,5.0e+00)]) }] " ++
        "}] " ++
        "}]]");
}
