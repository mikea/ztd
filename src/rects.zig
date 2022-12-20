const std = @import("std");
const geom = @import("geom.zig");

const Rect = geom.Rect;
const Vec = geom.Vec;

// array of rects optimized for r_tree usage.
pub const Rects = struct {
    _items: []Rect,
    cap: usize,

    pub fn init(allocator: std.mem.Allocator, comptime size: usize) !Rects {
        var items = try allocator.alloc(Rect, size);
        items.len = 0;
        return .{ ._items = items, .cap = size };
    }

    pub fn deinit(self: *Rects, allocator: std.mem.Allocator) void {
        self._items.len = self.cap;
        allocator.free(self._items);
    }

    pub fn copyFrom(self: *Rects, rects: []const Rect) void {
        self._items.len = rects.len;
        std.mem.copy(Rect, self._items, rects);
    }

    pub fn intersects(self: *const Rects, i: usize, rect: Rect) bool {
        return self._items[i].intersects(rect);
    }

    pub fn contains(self: *const Rects, i: usize, p: Vec) bool {
        return self._items[i].containsVec(p);
    }

    pub fn get(self: *const Rects, i: usize) Rect {
        return self._items[i];
    }

    pub fn append(self: *Rects, rect: Rect) void {
        std.debug.assert(self._items.len < self.cap);
        const i = self._items.len;
        self._items.len += 1;
        self._items[i] = rect;
    }

    pub fn pop(self: *Rects) Rect {
        std.debug.assert(self._items.len > 0);
        const result = self._items[self._items.len - 1];
        self._items.len -= 1;
        return result;
    }

    pub fn set(self: *Rects, i: usize, rect: Rect) void {
        self._items[i] = rect;
    }

    pub fn add(self: *Rects, i: usize, rect: Rect) void {
        self._items[i] = self._items[i].add(rect);
    }

    pub fn len(self: *const Rects) usize {
        return self._items.len;
    }

    pub fn clear(self: *Rects) void {
        self._items.len = 0;
    }

    // chooses a rect that will gain the least area if extended to include
    // given rect.
    pub fn chooseBestNode(self: *const Rects, rect: Rect) usize {
        // quick scan first
        for (self._items) |r, i| {
            if (r.containsRect(rect)) {
                return i;
            }
        }

        var result: usize = 0;
        var minDelta: f32 = std.math.inf_f32;

        for (self._items) |r, i| {
            const delta = r.add(rect).area() - r.area();

            if (delta < minDelta) {
                minDelta = delta;
                result = i;
            }
        }

        return result;
    }

    pub fn linearPickSeeds(self: *const Rects) [2]usize {
        const rects = self._items;
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

        pub fn format(
            self: *const @This(),
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.print("{s}", .{ self._items });
        }

};
