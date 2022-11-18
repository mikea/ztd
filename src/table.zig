const std = @import("std");

const TableError = error{
    RowNotFound,
};

pub const Id = u32;
const maxId: usize = 1 << 18;

pub const IdManager = struct {
    i: Id = 0,

    pub fn nextId(self: *@This()) Id {
        if (self.i == maxId) {
            std.log.err("too many ids allocated: max={}", .{maxId});
            @panic("too many ids");
        }
        const result = self.i;
        self.i += 1;
        return result;
    }
};

fn SparseSet(
    // index type
    comptime I: type,
    // maximum allowed index value
    comptime maxI: usize,
    // stored type
    comptime T: type,
) type {
    return struct {
        pub const Entry = struct {
            id: Id,
            value: T,
        };

        const DenseList = std.ArrayList(Entry);

        allocator: std.mem.Allocator,
        dense: DenseList,
        sparse: []I,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            const sparse = try allocator.alloc(I, maxI + 1);
            return .{ .allocator = allocator, .dense = DenseList.init(allocator), .sparse = sparse };
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.sparse);
            self.dense.deinit();
        }

        pub fn find(self: *@This(), i: I) ?*Entry {
            const denseIdx = self.sparse[i];
            if (denseIdx >= self.dense.items.len) {
                return null;
            }
            const entry = &self.dense.items[denseIdx];
            return if (entry.id == i) entry else null;
        }

        pub fn contains(self: *@This(), i: I) bool {
            return self.find(i) != null;
        }

        pub fn add(self: *@This(), i: I, t: T) !void {
            if (self.find(i)) |entry| {
                entry.value = t;
                return;
            }

            const denseIdx = @intCast(I, self.dense.items.len);
            try self.dense.append(.{ .id = i, .value = t });
            self.sparse[i] = denseIdx;
        }

        pub const Iterator = struct {
            l: *DenseList,
            i: u64,

            pub fn next(self: *@This()) ?*Entry {
                if (self.i >= self.l.items.len) return null;
                const result = &self.l.items[self.i];
                self.i += 1;
                return result;
            }
        };
 
        pub fn iterator(self: *@This()) Iterator {
            return .{ .l = &self.dense, .i = 0 };
        }

        pub fn get(self: *@This(), i: I) !*T {
            if (self.find(i)) |entry| {
                return &entry.value;
            }
            return TableError.RowNotFound;
        }
    };
}

pub fn Table(comptime T: type) type {
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

        pub fn get(self: *@This(), id: Id) !*T {
            return self.set.get(id);
        }
    };
}
