const std = @import("std");

const Error = error{
    RowNotFound,
};

pub fn SparseSet(
    // index type
    comptime I: type,
    // maximum allowed index value
    comptime maxI: usize,
    // stored type
    comptime T: type,
) type {
    return struct {
        pub const Entry = struct {
            id: I,
            value: T,
        };

        const DenseList = std.ArrayList(Entry);
        const ThisSparseSet = @This();

        allocator: std.mem.Allocator,
        dense: DenseList,
        sparse: []I,
        version: usize = 0,

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
            l: *ThisSparseSet,
            i: usize,
            v: usize,

            pub fn next(self: *@This()) ?*Entry {
                if (self.v != self.l.version) {
                    @panic("list was modified, not implemented");
                }
                if (self.i >= self.l.dense.items.len) return null;
                const result = &self.l.dense.items[self.i];
                self.i += 1;
                return result;
            }
        };

        pub fn iterator(self: *@This()) Iterator {
            return .{ .l = self, .i = 0, .v = self.version };
        }

        pub fn get(self: *@This(), i: I) !*T {
            if (self.find(i)) |entry| {
                return &entry.value;
            }
            return Error.RowNotFound;
        }

        pub fn delete(self: *@This(), i: I) !void {
            if (self.find(i) == null) {
                return;
            }
            self.version += 1;

            const denseIdx = self.sparse[i];
            const n = self.size();
            const last = self.dense.pop();

            if (denseIdx == n - 1) {
                return;
            }

            self.dense.items[denseIdx] = last;
            self.sparse[last.id] = self.sparse[i];
        }

        pub fn size(self: *const @This()) usize {
            return self.dense.items.len;
        }
    };
}

const expect = std.testing.expect;

const TestValue = struct { i: i32 };
const TestSet = SparseSet(u16, std.math.maxInt(u16), TestValue);

fn expectSet(set: *TestSet, expectedIds: []const u16, expectedIs: []const i32) !void {
    try std.testing.expectEqual(expectedIs.len, expectedIds.len);
    try std.testing.expectEqual(set.size(), expectedIds.len);

    var ids = try std.testing.allocator.alloc(u16, expectedIds.len);
    defer std.testing.allocator.free(ids);
    var is = try std.testing.allocator.alloc(i32, expectedIs.len);
    defer std.testing.allocator.free(is);

    var it = set.iterator();
    var i: usize = 0;
    while (it.next()) |entry| {
        ids[i] = entry.id;
        is[i] = entry.value.i;
        i += 1;
    }

    try std.testing.expectEqualSlices(
        u16,
        expectedIds,
        ids,
    );
    try std.testing.expectEqualSlices(
        i32,
        expectedIs,
        is,
    );
}

test "sparse set" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const leaked = gpa.deinit();
        if (leaked) @panic("Memory Leak Detected");
    }

    var set = try TestSet.init(allocator);
    defer set.deinit();

    try expect(0 == set.size());
    try expect(!set.contains(1024));

    try set.add(1024, .{ .i = 10 });
    try expect(1 == set.size());
    try expect(set.contains(1024));
    try expect(!set.contains(2048));

    try set.add(2048, .{ .i = 11 });
    try set.add(512, .{ .i = 9 });
    try set.add(256, .{ .i = 8 });
    try set.add(128, .{ .i = 7 });
    try set.add(1, .{ .i = 0 });
    try set.add(2, .{ .i = 1 });
    try set.add(4, .{ .i = 2 });
    try set.add(8, .{ .i = 3 });
    try set.add(16, .{ .i = 4 });
    try set.add(32, .{ .i = 5 });
    try set.add(64, .{ .i = 6 });

    try expectSet(&set, &[_]u16{ 1024, 2048, 512, 256, 128, 1, 2, 4, 8, 16, 32, 64 }, &[_]i32{ 10, 11, 9, 8, 7, 0, 1, 2, 3, 4, 5, 6 });

    {
        // test removing values while iterating
        var ids: [10]u16 = undefined;
        var is: [10]i32 = undefined;

        var it = set.iterator();
        var i: usize = 0;
        while (it.next()) |entry| {
            ids[i] = entry.id;
            is[i] = entry.value.i;

            if (entry.id == 2) {
                // delete one item before
                try set.delete(1);
                // one after
                try set.delete(32);
            }
            i += 1;
        }

        // todo: should include 64
        try std.testing.expectEqualSlices(
            u16,
            &[_]u16{ 1024, 2048, 512, 256, 128, 1, 2, 4, 8, 16 },
            &ids,
        );
        try std.testing.expectEqualSlices(
            i32,
            &[_]i32{ 10, 11, 9, 8, 7, 0, 1, 2, 3, 4 },
            &is,
        );

        try expectSet(&set, &[_]u16{ 1024, 2048, 512, 256, 128, 64, 2, 4, 8, 16 }, &[_]i32{ 10, 11, 9, 8, 7, 6, 1, 2, 3, 4 });
    }

    {
        // test removing the iterator value
        var ids: [9]u16 = undefined;
        var is: [9]i32 = undefined;

        var it = set.iterator();
        var i: usize = 0;
        while (it.next()) |entry| {
            ids[i] = entry.id;
            is[i] = entry.value.i;

            if (entry.id == 512) {
                try set.delete(512);
            }
            i += 1;
        }

        // todo: should include 16
        try std.testing.expectEqualSlices(
            u16,
            &[_]u16{ 1024, 2048, 512, 256, 128, 64, 2, 4, 8 },
            &ids,
        );
        try std.testing.expectEqualSlices(
            i32,
            &[_]i32{ 10, 11, 9, 8, 7, 6, 1, 2, 3 },
            &is,
        );

        try expectSet(&set, &[_]u16{ 1024, 2048, 16, 256, 128, 64, 2, 4, 8 }, &[_]i32{ 10, 11, 4, 8, 7, 6, 1, 2, 3 });
    }
}
