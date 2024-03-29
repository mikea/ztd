const std = @import("std");

pub const Vec = struct {
    pub const zero = Vec{ .x = 0, .y = 0 };

    x: f32,
    y: f32,

    // auto cast integers to float
    pub fn init(x: anytype, y: anytype) Vec {
        return .{
            .x = if (@TypeOf(x) == f32) x else @intToFloat(f32, x),
            .y = if (@TypeOf(y) == f32) y else @intToFloat(f32, y),
        };
    }

    pub fn initAngle(angleRad: f32) Vec {
        return .{ .x = std.math.cos(angleRad), .y = std.math.sin(angleRad) };
    }

    pub fn add(a: Vec, b: Vec) Vec {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn minus(a: Vec, b: Vec) Vec {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn dist(from: Vec, to: Vec) f32 {
        return minus(to, from).norm();
    }

    pub fn dist2(from: Vec, to: Vec) f32 {
        return minus(to, from).norm2();
    }

    pub fn dir(from: Vec, to: Vec) Vec {
        return minus(to, from).normalized();
    }

    pub fn ratio(v1: Vec, v2: Vec) Vec {
        return .{ .x = v1.x / v2.x, .y = v1.y / v2.y };
    }

    pub fn mul(v1: Vec, v2: Vec) Vec {
        return .{ .x = v1.x * v2.x, .y = v1.y * v2.y };
    }

    pub fn div(v1: Vec, v2: Vec) Vec {
        return .{ .x = v1.x / v2.x, .y = v1.y / v2.y };
    }

    pub fn scale(self: *const Vec, a: f32) Vec {
        return .{ .x = self.x * a, .y = self.y * a };
    }

    pub fn norm(self: *const Vec) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn norm2(self: *const Vec) f32 {
        return self.x * self.x + self.y * self.y;
    }

    fn normalized(self: *const Vec) Vec {
        const n = self.norm();
        return .{ .x = self.x / n, .y = self.y / n };
    }

    fn area(self: *const Vec) f32 {
        return std.math.fabs(self.x * self.y);
    }

    pub fn format(
        self: Vec,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("({},{})", .{
            self.x,
            self.y,
        });
    }

    pub fn angle(self: *const Vec) f32 {
        return std.math.atan2(f32, self.y, self.x);
    }

    pub fn min(self: *const Vec, v: Vec) Vec {
        return .{ .x = std.math.min(self.x, v.x), .y = std.math.min(self.y, v.y) };
    }

    pub fn max(self: *const Vec, v: Vec) Vec {
        return .{ .x = std.math.max(self.x, v.x), .y = std.math.max(self.y, v.y) };
    }

    pub fn grid(self: *const Vec, gridSize: Vec) Vec {
        return .{ .x = gridSize.x * @round(self.x / gridSize.x), .y = gridSize.y * @round(self.y / gridSize.y) };
    }

    pub fn asArray(self: *const Vec) [2]f32 {
        return [_]f32{ self.x, self.y };
    }
};

pub const Rect = struct {
    a: Vec,
    b: Vec,

    pub fn init(x1: f32, y1: f32, x2: f32, y2: f32) Rect {
        return .{ .a = .{ .x = x1, .y = y1 }, .b = .{ .x = x2, .y = y2 } };
    }

    pub fn initInt(x1: anytype, y1: anytype, x2: anytype, y2: anytype) Rect {
        return .{
            .a = .{ .x = @intToFloat(f32, x1), .y = @intToFloat(f32, y1) },
            .b = .{ .x = @intToFloat(f32, x2), .y = @intToFloat(f32, y2) },
        };
    }

    pub fn initCentered(c: Vec, aSize: Vec) Rect {
        const s2 = aSize.scale(0.5);
        return .{ .a = c.minus(s2), .b = c.add(s2) };
    }

    pub fn initSized(o: Vec, aSize: Vec) Rect {
        return .{ .a = o, .b = o.add(aSize) };
    }

    pub fn intersects(r1: Rect, r2: Rect) bool {
        // ((X,Y),(A,B)) and ((X1,Y1),(A1,B1))
        // (X,Y) = (r1.a.x, r1.a.y)
        // (A,B) = (r1.b.x, r1.b.y)
        // (X1,Y1) = (r2.a.x, r2.a.y)
        // (A1,B1) = (r2.b.x, r2.b.y)
        // A<X1 or A1<X or B<Y1 or B1<Y
        return ((r1.b.x >= r2.a.x) and (r2.b.x >= r1.a.x) and (r1.b.y >= r2.a.y) and (r2.b.y >= r1.a.y));
    }

    pub fn size(self: *const Rect) Vec {
        return self.b.minus(self.a);
    }

    pub fn center(self: *const Rect) Vec {
        return .{ .x = (self.a.x + self.b.x) / 2, .y = (self.a.y + self.b.y) / 2 };
    }

    pub fn translate(self: *const Rect, v: Vec) Rect {
        return .{ .a = .{ .x = self.a.x + v.x, .y = self.a.y + v.y }, .b = .{ .x = self.b.x + v.x, .y = self.b.y + v.y } };
    }

    pub fn height(self: *const Rect) f32 {
        return self.b.y - self.a.y;
    }

    pub fn containsVec(self: *const Rect, v: Vec) bool {
        return v.x >= self.a.x and v.x <= self.b.x and v.y >= self.a.y and v.y <= self.b.y;
    }

    pub fn containsRect(self: *const Rect, r: Rect) bool {
        return r.a.x >= self.a.x and r.a.y >= self.a.y and r.b.x <= self.b.x and r.b.y <= self.b.y;
    }

    pub fn add(self: *const Rect, r: Rect) Rect {
        return .{ .a = .{
            .x = if (self.a.x < r.a.x) self.a.x else r.a.x,
            .y = if (self.a.y < r.a.y) self.a.y else r.a.y,
        }, .b = .{
            .x = if (self.b.x > r.b.x) self.b.x else r.b.x,
            .y = if (self.b.y > r.b.y) self.b.y else r.b.y,
        } };
    }

    pub fn area(self: *const Rect) f32 {
        return (self.b.x - self.a.x) * (self.b.y - self.a.y);
    }

    pub fn grid(self: *const Rect, gridX: f32, gridY: f32) Rect {
        const c = self.center();
        const sz = self.size();
        return Rect.initCentered(gridX * @floor(c.x / gridX), gridY * @floor(c.y / gridY), sz.w, sz.h);
    }

    pub fn format(
        self: Rect,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("[{},{}]", .{
            self.a,
            self.b,
        });
    }
};
