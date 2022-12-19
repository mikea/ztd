const std = @import("std");

const Error = error{
    RowNotFound,
};

pub fn DenseSet(
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

        const ThisDenseSet = @This();

        allocator: std.mem.Allocator,
        ids: []I,
        values: []T,
        sparse: []I,
        len: usize = 0,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return .{
                .allocator = allocator,
                .ids = try allocator.alloc(I, maxI + 1),
                .values = try allocator.alloc(T, maxI + 1),
                .sparse = try allocator.alloc(I, maxI + 1),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.sparse);
            self.allocator.free(self.ids);
            self.allocator.free(self.values);
        }

        pub fn find(self: *@This(), i: I) ?*T {
            const denseIdx = self.sparse[i];
            if (denseIdx < self.len and self.ids[denseIdx] == i) {
                return &self.values[denseIdx];
            }
            return null;
        }

        pub fn set(self: *@This(), i: I, t: T) void {
            _ = self.insertOrUpdate(i, t);
        }

        // returns true if insert happens, false otherwise
        pub fn insertOrUpdate(self: *@This(), i: I, t: T) bool {
            const denseIdx = self.sparse[i];
            if (denseIdx < self.len and self.ids[denseIdx] == i) {
                self.values[denseIdx] = t;
                return false;
            } else {
                const idx = @intCast(I, self.len);
                self.ids[idx] = i;
                self.values[idx] = t;
                self.sparse[i] = idx;
                self.len += 1;
                return true;
            }
        }

        pub fn get(self: *@This(), i: I) *T {
            const denseIdx = self.sparse[i];
            if (denseIdx < self.len and self.ids[denseIdx] == i) {
                return &self.values[denseIdx];
            }
            @panic("row not found");
        }

        pub fn delete(self: *@This(), i: I) bool {
            if (self.find(i) == null) {
                return false;
            }

            const denseIdx = self.sparse[i];
            const last = self.len - 1;
            self.len -= 1;

            if (denseIdx == last) {
                return true;
            }

            const lastValue = self.values[last];
            const lastId = self.ids[last];
            self.values[denseIdx] = lastValue;
            self.ids[denseIdx] = lastId;
            self.sparse[lastId] = self.sparse[i];
            return true;
        }
    };
}
