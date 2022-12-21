const std = @import("std");
const geom = @import("geom.zig");

const Rect = geom.Rect;
const Vec = geom.Vec;

// array of rects optimized for r_tree usage.
pub fn Rects(comptime cap: usize, comptime blockSize: usize) type {
    if (comptime cap % blockSize != 0) {
        @compileLog("cap=", cap, "blockSize=", blockSize);
        @compileError("Rects cap doesn't align with vector size");
    }

    return struct {
        ax: []f32,
        ay: []f32,
        bx: []f32,
        by: []f32,
        len: usize = 0,
        capacity: usize = cap,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            return .{
                .ax = try allocator.alloc(f32, cap),
                .ay = try allocator.alloc(f32, cap),
                .bx = try allocator.alloc(f32, cap),
                .by = try allocator.alloc(f32, cap),
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.ax);
            allocator.free(self.ay);
            allocator.free(self.bx);
            allocator.free(self.by);
        }

        pub fn copyFrom(self: *@This(), rects: []const Rect) void {
            self.len = rects.len;
            for (rects) |r, i| {
                self.set(i, r);
            }
        }

        pub fn intersects(self: *const @This(), i: usize, rect: Rect) bool {
            return self.get(i).intersects(rect);
        }

        pub fn containsVec(self: *const @This(), i: usize, p: Vec) bool {
            return self.get(i).containsVec(p);
        }

        pub fn get(self: *const @This(), i: usize) Rect {
            return Rect.init(self.ax[i], self.ay[i], self.bx[i], self.by[i]);
        }

        pub fn append(self: *@This(), rect: Rect) void {
            std.debug.assert(self.len < cap);
            const i = self.len;
            self.len += 1;
            self.set(i, rect);
        }

        pub fn pop(self: *@This()) Rect {
            std.debug.assert(self.len > 0);
            self.len -= 1;
            return self.get(self.len);
        }

        pub fn set(self: *@This(), i: usize, r: Rect) void {
            self.ax[i] = r.a.x;
            self.ay[i] = r.a.y;
            self.bx[i] = r.b.x;
            self.by[i] = r.b.y;
        }

        pub fn add(self: *@This(), i: usize, rect: Rect) void {
            self.set(i, self.get(i).add(rect));
        }

        pub fn clear(self: *@This()) void {
            self.len = 0;
        }

        pub fn containsRect(self: *const @This(), i: usize, r: Rect) bool {
            return r.a.x >= self.ax[i] and r.a.y >= self.ay[i] and r.b.x <= self.bx[i] and r.b.y <= self.by[i];
        }

        fn findContainsRect(self: *const @This(), r: Rect) ?usize {
            const F = @Vector(blockSize, f32);
            const U = @Vector(blockSize, u1);
            const B = @Vector(blockSize, bool);

            const rax: F = @splat(blockSize, r.a.x);
            const ray: F = @splat(blockSize, r.a.y);
            const rbx: F = @splat(blockSize, r.b.x);
            const rby: F = @splat(blockSize, r.b.y);

            var block: usize = 0;
            while (block < comptime cap / blockSize) : (block += 1) {
                const offset = block * blockSize;
                if (offset >= self.len) {
                    break;
                }

                const ax: F = self.ax[offset..][0..blockSize].*;
                const ay: F = self.ay[offset..][0..blockSize].*;
                const bx: F = self.bx[offset..][0..blockSize].*;
                const by: F = self.by[offset..][0..blockSize].*;

                const v1 = rax >= ax;
                const v2 = ray >= ay;
                const v3 = rbx <= bx;
                const v4 = rby <= by;

                // const containsRect = r.a.x >= self.ax[i] and r.a.y >= self.ay[i] and r.b.x <= self.bx[i] and r.b.y <= self.by[i];
                // const c: V =  (rax >= ax) and (ray >= ay) & (rbx <= bx) & (rby <= by);
                // zig compiler can't do boolean operations for vectors of bool, hence the bitcasts.
                const c = @bitCast(B, @bitCast(U, v1) & @bitCast(U, v2) & @bitCast(U, v3) & @bitCast(U, v4));
                if (std.simd.firstTrue(c)) |i| {
                    if (i + offset >= self.len) {
                        return null;
                    }
                    return i + offset;
                }
            }

            return null;
        }

        // chooses a rect that will gain the least area if extended to include
        // given rect.
        pub fn chooseBestNode(self: *const @This(), r: Rect) usize {
            // quick scan first
            if (self.findContainsRect(r)) |idx| {
                return idx;
            }


            // SIMD instructions of the following code:
            // var i: usize = 0;
            // while (i < self.len) : (i += 1) {
            //     const r = self.get(i);
            //     const delta = r.add(rect).area() - r.area();

            //     if (delta < minDelta) {
            //         minDelta = delta;
            //         result = i;
            //     }
            // }

            // return result;

            const F = @Vector(blockSize, f32);

            var result: usize = 0;
            var minDelta: f32 = std.math.inf_f32;

            const rax: F = @splat(blockSize, r.a.x);
            const ray: F = @splat(blockSize, r.a.y);
            const rbx: F = @splat(blockSize, r.b.x);
            const rby: F = @splat(blockSize, r.b.y);

            var block: usize = 0;
            while (block < comptime cap / blockSize) : (block += 1) {
                const offset = block * blockSize;
                if (offset >= self.len) {
                    break;
                }

                const ax: F = self.ax[offset..][0..blockSize].*;
                const ay: F = self.ay[offset..][0..blockSize].*;
                const bx: F = self.bx[offset..][0..blockSize].*;
                const by: F = self.by[offset..][0..blockSize].*;

                const area = (bx - ax) * (by - ay);

                // r.add(rect)

                // return .{ .a = .{
                //     .x = if (self.a.x < r.a.x) self.a.x else r.a.x,
                //     .y = if (self.a.y < r.a.y) self.a.y else r.a.y,
                // }, .b = .{
                //     .x = if (self.b.x > r.b.x) self.b.x else r.b.x,
                //     .y = if (self.b.y > r.b.y) self.b.y else r.b.y,
                // } };
                const ax1 = @select(f32, ax < rax, ax, rax);
                const ay1 = @select(f32, ay < ray, ay, ray);
                const bx1 = @select(f32, bx > rbx, bx, rbx);
                const by1 = @select(f32, by > rby, by, rby);

                const area1 = (bx1 - ax1) * (by1 - ay1);
                const delta = area1 - area;

                var i: usize = 0;
                while ( i < blockSize) : (i+=1) {
                    if (i + offset > self.len) {
                        break;
                    }
                    std.debug.assert(delta[i] >= 0);
                    if (delta[i] > minDelta) {
                        result = i + offset;
                        minDelta = delta[i];
                    }
                }
            }

            return result;
        }

        pub fn linearPickSeeds(self: *const @This()) [2]usize {
            // LPS1 Find extreme rectangles along all dimensions
            const first = self.get(0);
            const last = self.get(self.len - 1);

            var lowestX = first.a.x;
            var lowestY = first.a.y;
            var highestX = first.b.x;
            var highestY = first.b.y;

            var highestLowX = first.a.x;
            var highestLowXIdx: usize = 0;
            var lowestHighX = last.b.x;
            var lowestHighXIdx: usize = self.len - 1;

            var highestLowY = first.a.y;
            var highestLowYIdx: usize = 0;
            var lowestHighY = last.b.y;
            var lowestHighYIdx: usize = self.len - 1;

            var i: usize = 0;
            while (i < self.len) : (i += 1) {
                const rect = self.get(i);
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
            try writer.writeAll("{ ");
            var i: usize = 0;
            while (i < self.len) : (i += 1) {
                if (i > 0) {
                    try writer.writeAll(", ");
                }
                try writer.print("{s}", .{self.get(i)});
            }
            try writer.writeAll(" }");
        }
    };
}

