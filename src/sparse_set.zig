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
            value: *T,
        };

        const ThisSparseSet = @This();

        allocator: std.mem.Allocator,
        ids: std.ArrayList(I),
        values: std.ArrayList(T),
        sparse: []I,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return .{
                .allocator = allocator,
                .ids = std.ArrayList(I).init(allocator),
                .values = std.ArrayList(T).init(allocator),
                .sparse = try allocator.alloc(I, maxI + 1),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.sparse);
            self.ids.deinit();
            self.values.deinit();
        }

        pub fn find(self: *@This(), i: I) ?*T {
            const denseIdx = self.sparse[i];
            if (denseIdx < self.ids.items.len and self.ids.items[denseIdx] == i) {
                return &self.values.items[denseIdx];
            }
            return null;
        }

        pub fn findEntry(self: *@This(), i: I) ?Entry {
            const denseIdx = self.sparse[i];
            if (denseIdx < self.ids.items.len and self.ids.items[denseIdx] == i) {
                return .{ .id = i, .value = &self.values.items[denseIdx] };
            }
            return null;
        }

        pub fn contains(self: *@This(), i: I) bool {
            return self.find(i) != null;
        }

        pub fn set(self: *@This(), i: I, t: T) !void {
            _ = try self.insertOrUpdate(i, t);
        }

        // returns true if insert happens, false otherwise
        pub fn insertOrUpdate(self: *@This(), i: I, t: T) !bool {
            const denseIdx = self.sparse[i];
            if (denseIdx < self.ids.items.len and self.ids.items[denseIdx] == i) {
                self.values.items[denseIdx] = t;
                return false;
            } else {
                const idx = @intCast(I, self.ids.items.len);
                try self.ids.append(i);
                try self.values.append(t);
                self.sparse[i] = idx;
                return true;
            }
        }

        pub const Iterator = struct {
            l: *ThisSparseSet,
            i: usize,

            pub fn next(self: *@This()) ?Entry {
                if (self.i >= self.l.ids.items.len) return null;
                const id = self.l.ids.items[self.i];
                const value = &self.l.values.items[self.i];
                self.i += 1;
                return .{ .id = id, .value = value };
            }
        };

        pub fn iterator(self: *@This()) Iterator {
            return .{ .l = self, .i = 0 };
        }

        pub fn get(self: *@This(), i: I) *T {
            const denseIdx = self.sparse[i];
            if (denseIdx < self.ids.items.len and self.ids.items[denseIdx] == i) {
                return &self.values.items[denseIdx];
            }
            @panic("row not found");
        }

        pub fn delete(self: *@This(), i: I) void {
            if (self.find(i) == null) {
                return;
            }

            const denseIdx = self.sparse[i];
            const n = self.size();

            const lastValue = self.values.pop();
            const lastId = self.ids.pop();

            if (denseIdx == n - 1) {
                return;
            }

            self.values.items[denseIdx] = lastValue;
            self.ids.items[denseIdx] = lastId;
            self.sparse[lastId] = self.sparse[i];
        }

        pub fn pop(self: *@This()) I {
            self.values.pop();
            return self.ids.pop();
        }

        pub fn size(self: *const @This()) usize {
            return self.ids.items.len;
        }

        pub fn clear(self: *@This()) void {
            self.ids.clearRetainingCapacity();
            self.values.clearRetainingCapacity();
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

    try set.set(1024, .{ .i = 10 });
    try expect(1 == set.size());
    try expect(set.contains(1024));
    try expect(!set.contains(2048));

    try set.set(2048, .{ .i = 11 });
    try set.set(512, .{ .i = 9 });
    try set.set(256, .{ .i = 8 });
    try set.set(128, .{ .i = 7 });
    try set.set(1, .{ .i = 0 });
    try set.set(2, .{ .i = 1 });
    try set.set(4, .{ .i = 2 });
    try set.set(8, .{ .i = 3 });
    try set.set(16, .{ .i = 4 });
    try set.set(32, .{ .i = 5 });
    try set.set(64, .{ .i = 6 });

    try expectSet(&set, &[_]u16{ 1024, 2048, 512, 256, 128, 1, 2, 4, 8, 16, 32, 64 }, &[_]i32{ 10, 11, 9, 8, 7, 0, 1, 2, 3, 4, 5, 6 });

    // {
    //     // test removing values while iterating
    //     var ids: [10]u16 = undefined;
    //     var is: [10]i32 = undefined;

    //     var it = set.iterator();
    //     var i: usize = 0;
    //     while (it.next()) |entry| {
    //         ids[i] = entry.id;
    //         is[i] = entry.value.i;

    //         if (entry.id == 2) {
    //             // delete one item before
    //             try set.delete(1);
    //             // one after
    //             try set.delete(32);
    //         }
    //         i += 1;
    //     }

    //     // todo: should include 64
    //     try std.testing.expectEqualSlices(
    //         u16,
    //         &[_]u16{ 1024, 2048, 512, 256, 128, 1, 2, 4, 8, 16 },
    //         &ids,
    //     );
    //     try std.testing.expectEqualSlices(
    //         i32,
    //         &[_]i32{ 10, 11, 9, 8, 7, 0, 1, 2, 3, 4 },
    //         &is,
    //     );

    //     try expectSet(&set, &[_]u16{ 1024, 2048, 512, 256, 128, 64, 2, 4, 8, 16 }, &[_]i32{ 10, 11, 9, 8, 7, 6, 1, 2, 3, 4 });
    // }

    // {
    //     // test removing the iterator value
    //     var ids: [9]u16 = undefined;
    //     var is: [9]i32 = undefined;

    //     var it = set.iterator();
    //     var i: usize = 0;
    //     while (it.next()) |entry| {
    //         ids[i] = entry.id;
    //         is[i] = entry.value.i;

    //         if (entry.id == 512) {
    //             try set.delete(512);
    //         }
    //         i += 1;
    //     }

    //     // todo: should include 16
    //     try std.testing.expectEqualSlices(
    //         u16,
    //         &[_]u16{ 1024, 2048, 512, 256, 128, 64, 2, 4, 8 },
    //         &ids,
    //     );
    //     try std.testing.expectEqualSlices(
    //         i32,
    //         &[_]i32{ 10, 11, 9, 8, 7, 6, 1, 2, 3 },
    //         &is,
    //     );

    //     try expectSet(&set, &[_]u16{ 1024, 2048, 16, 256, 128, 64, 2, 4, 8 }, &[_]i32{ 10, 11, 4, 8, 7, 6, 1, 2, 3 });
    // }
}
