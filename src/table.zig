const std = @import("std");
const SparseSet = @import("sparse_set.zig").SparseSet;

pub fn Table(comptime Id: type, comptime maxId: Id, comptime T: type) type {
    return struct {
        const Set = SparseSet(Id, maxId, T);
        pub const Entry = Set.Entry;
        pub const Iterator = Set.Iterator;

        set: Set = undefined,

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
    };
}

