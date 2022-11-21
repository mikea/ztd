// R-Tree implementation
// Reference: Guttman, R-trees: A dynamic index structure for spatial searching
//
const std = @import("std");
const geom = @import("geom.zig");

const Vec2 = geom.Vec2;
const Rect = geom.Rect;
const inf = std.math.inf_f32;
const assert = std.debug.assert;

const NodeType = enum { leaf, middle };

pub fn RTree(comptime Id: type, comptime leafSize: usize, comptime middleSize: usize) type {
    return struct {
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
            parent: ?*Node = null,
            rect: Rect = Rect.init(0, 0, 0, 0),
            len: usize = 0,

            items: union(NodeType) {
                leaf: [leafSize + 1]Entry,
                middle: [middleSize + 1]*Node,
            },

            fn initMiddle(allocator: std.mem.Allocator, initialChildren: []const *Node) !*Node {
                var node = try allocator.create(Node);
                var rect = initialChildren[0].rect;
                for (initialChildren) |child| {
                    rect = rect.add(child.rect);
                    child.parent = node;
                }
                node.* = .{ .len = initialChildren.len, .rect = rect, .items = .{ .middle = undefined } };
                std.mem.copy(*Node, &node.items.middle, initialChildren);
                return node;
            }

            fn initLeaf(allocator: std.mem.Allocator, entry: Entry) !*Node {
                var node = try allocator.create(Node);
                node.* = .{ .len = 1, .rect = entry.rect, .items = .{ .leaf = undefined } };
                node.items.leaf[0] = entry;
                return node;
            }

            fn addEntry(self: *@This(), entry: Entry) void {
                self.items.leaf[self.len] = entry;
                self.len += 1;
                if (self.len == 1) {
                    self.rect = entry.rect;
                } else {
                    self.rect = self.rect.add(entry.rect);
                }
            }

            fn addChild(self: *@This(), child: *Node) void {
                self.items.middle[self.len] = child;
                self.len += 1;
                if (self.len == 1) {
                    self.rect = child.rect;
                } else {
                    self.rect = self.rect.add(child.rect);
                }
            }

            pub fn format(
                self: *const @This(),
                comptime _: []const u8,
                _: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                switch (self.*.items) {
                    .leaf => |entries| try writer.print("Leaf[rect={}, items={s}]", .{ self.rect, entries[0..self.len] }),
                    .middle => |children| {
                        try writer.print("Middle[rect={}, children={s}]", .{ self.rect, children[0..self.len] });
                    },
                }
            }
        };

        allocator: std.mem.Allocator,

        root: *Node,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            const root = try allocator.create(Node);
            root.* = .{ .items = .{ .leaf = .{} } };
            return .{ .allocator = allocator, .root = root };
        }

        pub fn deinit(self: *@This()) void {
            self.destroy(self.root);
        }

        fn destroy(self: *@This(), node: *Node) void {
            switch (node.*.items) {
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
            const leafNode = self.chooseLeaf(rect);
            leafNode.addEntry(.{ .id = id, .rect = rect });
            adjustTree(leafNode.parent, rect);

            if (leafNode.len == leafNode.items.leaf.len) {
                // leaf doesn't have enough room, split it
                var splitNodes = try self.splitLeaf(leafNode);
                try self.replaceSplitChild(leafNode.parent, leafNode, splitNodes);
            }
        }

        fn chooseLeaf(self: *@This(), rect: Rect) *Node {
            var node = self.root;
            while (true) {
                switch (node.*.items) {
                    .leaf => return node,
                    .middle => |children| node = chooseNode(children[0..node.len], rect),
                }
            }
        }

        fn adjustTree(node: ?*Node, rect: Rect) void {
            var n = node;
            while (n != null) {
                n.?.rect = n.?.rect.add(rect);
                n = n.?.parent;
            }
        }

        fn splitLeaf(self: *@This(), node: *Node) ![2]*Node {
            var entries = node.items.leaf;
            // QS1 pick first entry for each group
            const seeds = linearPickSeeds(Entry, &entries);
            var result: [2]*Node = undefined;

            for (seeds) |seed, i| {
                result[i] = try Node.initLeaf(self.allocator, entries[seed]);
            }

            // add the rest
            for (entries) |entry, i| {
                if (i != seeds[0] and i != seeds[1]) {
                    chooseNode(&result, entry.rect).addEntry(entry);
                }
            }

            return result;
        }

        fn splitMiddle(self: *@This(), node: *Node) ![2]*Node {
            var children = node.items.middle;

            // QS1 pick first entry for each group
            const seeds = linearPickSeeds(*Node, &children);
            var result = [2]*Node{
                try Node.initMiddle(self.allocator, &[_]*Node{children[seeds[0]]}),
                try Node.initMiddle(self.allocator, &[_]*Node{children[seeds[1]]}),
            };

            // add the rest
            for (children) |child, i| {
                if (i != seeds[0] and i != seeds[1]) {
                    chooseNode(&result, child.rect).addChild(child);
                }
            }

            return result;
        }

        fn replaceSplitChild(self: *@This(), maybeParent: ?*Node, child: *Node, split: [2]*Node) !void {
            defer self.allocator.destroy(child);
            
            if (maybeParent == null) {
                // splitting the root
                assert(child == self.root);
                const newRoot = try Node.initMiddle(self.allocator, &split);
                self.root = newRoot;
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
            try self.maybeSplitMiddle(parent);
        }

        fn maybeSplitMiddle(self: *@This(), node: *Node) error{OutOfMemory}!void {
            if (node.len < node.items.middle.len) {
                return;
            }

            var splitNodes = try self.splitMiddle(node);
            try self.replaceSplitChild(node.parent, node, splitNodes);
        }

        // chooses a node that will gain the least area if extended to include
        // given rect.
        fn chooseNode(nodes: []const *Node, rect: Rect) *Node {
            var result: *Node = nodes[0];
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

                if (entry.rect.a.x > highestLowX) {
                    highestLowX = entry.rect.a.x;
                    highestLowXIdx = i;
                }
                if (entry.rect.a.y > highestLowY) {
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
                return [_]usize{ lowestHighXIdx, highestLowXIdx };
            } else {
                return [_]usize{ lowestHighYIdx, highestLowYIdx };
            }
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

const expect = std.testing.expect;

fn expectFormat(tree: anytype, expected: []const u8) !void {
    const actual = try std.fmt.allocPrint(std.testing.allocator, "{s}", .{tree});
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

test "rtree" {
    var tree = try RTree(u16, 4, 3).init(std.testing.allocator);
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
}
