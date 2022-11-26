const std = @import("std");
const SparseSet = @import("sparse_set.zig").SparseSet;
const geom = @import("geom.zig");
const Rect = geom.Rect;
const RTree = @import("r_tree.zig").RTree;

pub fn Table(comptime Id: type, comptime maxId: Id, comptime T: type) type {
    return struct {
        const Set = SparseSet(Id, maxId, T);
        pub const Entry = Set.Entry;
        pub const Iterator = Set.Iterator;

        set: Set,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return .{ .set = try Set.init(allocator) };
        }

        pub fn deinit(self: *@This()) void {
            self.set.deinit();
        }

        pub fn add(self: *@This(), id: Id, t: T) !void {
            return self.set.add(id, t);
        }

        pub fn iterator(self: *@This()) Iterator {
            return self.set.iterator();
        }

        pub fn find(self: *@This(), id: Id) ?*Entry {
            return self.set.find(id);
        }

        pub fn get(self: *@This(), id: Id) !*T {
            return self.set.get(id);
        }

        pub fn delete(self: *@This(), id: Id) !void {
            return self.set.delete(id);
        }

        pub fn size(self: *const @This()) usize {
            return self.set.size();
        }

        pub fn update(self: *@This(), id: Id, t: Rect) !void {
            return self.set.add(id, t);
        }
    };
}

// A table of bounded rectangles that maintanes RTree index.
pub fn RTable(comptime Id: type, comptime maxId: Id) type {
    return struct {
        const Set = SparseSet(Id, maxId, Rect);
        const Tree = RTree(Id, 300, 100);

        pub const Entry = Set.Entry;
        // pub const Iterator = Set.Iterator;

        set: Set,
        tree: Tree,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return .{ .set = try Set.init(allocator), .tree = try Tree.init(allocator) };
        }

        pub fn deinit(self: *@This()) void {
            self.set.deinit();
            self.tree.deinit();
        }

        pub fn add(self: *@This(), id: Id, t: Rect) !void {
            std.debug.assert(self.set.find(id) == null);
            try self.set.add(id, t);
            try self.tree.insert(id, t);
        }

        pub fn get(self: *@This(), id: Id) !Rect {
            return (try self.set.get(id)).*;
        }
 
         pub fn find(self: *@This(), id: Id) ?Entry {
            return (self.set.find(id) orelse return null).*;
        }
 
        pub fn delete(self: *@This(), id: Id) !void {
            return self.set.delete(id);
        }

        pub fn update(self: *@This(), id: Id, t: Rect) !void {
            const oldRect = try self.get(id);
            try self.set.add(id, t);
            try self.tree.update(id, oldRect, t);
        }

        pub fn findIntersect(self: *const @This(), rect: Rect, comptime CallbackThis: type, callbackThis: *CallbackThis, comptime callback: fn (that: *CallbackThis, id: Id, rect: Rect) error{OutOfMemory}!void) !void {
            try self.tree.findIntersect(rect, CallbackThis, callbackThis, callback);
        }
  };
}