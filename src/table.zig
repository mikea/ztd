const std = @import("std");
const SparseSet = @import("sparse_set.zig").SparseSet;
const geom = @import("geom.zig");
const Rect = geom.Rect;
const Vec = geom.Vec;
const RTree = @import("r_tree.zig").RTree;

pub fn Table(comptime Id: type, comptime maxId: Id, comptime T: type) type {
    return struct {
        const Set = SparseSet(Id, maxId, T);
        pub const Entry = Set.Entry;
        const Iterator = Set.Iterator;

        sparse: Set,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return .{ .sparse = try Set.init(allocator) };
        }

        pub fn deinit(self: *@This()) void {
            self.sparse.deinit();
        }

        pub fn set(self: *@This(), id: Id, t: T) !void {
            return self.sparse.set(id, t);
        }

        pub fn iterator(self: *@This()) Iterator {
            return self.sparse.iterator();
        }

        pub fn find(self: *@This(), id: Id) ?*T {
            if (self.sparse.find(id)) |*entry| {
                return &entry.*.value;
            }
            return null;
        }

        pub fn findEntry(self: *@This(), id: Id) ?*Entry {
            return self.sparse.find(id);
        }

        pub fn get(self: *@This(), id: Id) !*T {
            return self.sparse.get(id);
        }

        pub fn delete(self: *@This(), id: Id) !void {
            return self.sparse.delete(id);
        }

        pub fn size(self: *const @This()) usize {
            return self.sparse.size();
        }

        pub fn update(self: *@This(), id: Id, t: Rect) !void {
            return self.sparse.add(id, t);
        }
    };
}

// A table of bounded rectangles that maintanes RTree index.
pub fn RTable(comptime Id: type, comptime maxId: Id) type {
    return struct {
        const Set = SparseSet(Id, maxId, Rect);
        const Tree = RTree(Id, maxId, 300, 100);

        pub const Entry = Set.Entry;
        // pub const Iterator = Set.Iterator;

        sparse: Set,
        tree: Tree,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return .{ .sparse = try Set.init(allocator), .tree = try Tree.init(allocator) };
        }

        pub fn deinit(self: *@This()) void {
            self.sparse.deinit();
            self.tree.deinit();
        }

        pub fn add(self: *@This(), id: Id, t: Rect) !void {
            std.debug.assert(self.sparse.find(id) == null);
            try self.sparse.set(id, t);
            try self.tree.insert(id, t);
        }

        pub fn set(self: *@This(), id: Id, t: Rect) !void {
            if (try self.sparse.insertOrUpdate(id, t)) {
                try self.tree.insert(id, t);
            } else {
                try self.tree.update(id, t);
            }
        }

        pub fn get(self: *@This(), id: Id) !Rect {
            return (try self.sparse.get(id)).*;
        }

        pub fn find(self: *@This(), id: Id) ?Entry {
            return (self.sparse.find(id) orelse return null).*;
        }

        pub fn delete(self: *@This(), id: Id) !void {
            return self.sparse.delete(id);
        }

        pub fn update(self: *@This(), id: Id, t: Rect) !void {
            try self.sparse.set(id, t);
            try self.tree.update(id, t);
        }

        pub fn findIntersect(self: *const @This(), rect: Rect, comptime CallbackThis: type, callbackThis: *CallbackThis, comptime callback: fn (that: *CallbackThis, id: Id, rect: Rect) error{OutOfMemory}!void) !void {
            try self.tree.findIntersect(rect, CallbackThis, callbackThis, callback);
        }

        pub fn findPoint(self: *const @This(), p: Vec, comptime CallbackThis: type, callbackThis: *CallbackThis, comptime callback: fn (that: *CallbackThis, id: Id, rect: Rect) error{OutOfMemory}!void) !void {
            try self.tree.findPoint(p, CallbackThis, callbackThis, callback);
        }
    };
}
