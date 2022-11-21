const std = @import("std");

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn minus(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn dist(from: Vec2, to: Vec2) f32 {
        return minus(to, from).norm();
    }

    fn dir(from: Vec2, to: Vec2) Vec2 {
        return minus(to, from).normalized();
    }

    pub fn mul(self: *const Vec2, a: f32) Vec2 {
        return .{ .x = self.x * a, .y = self.y * a };
    }

    pub fn norm(self: *const Vec2) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    fn normalized(self: *const Vec2) Vec2 {
        const n = self.norm();
        return .{ .x = self.x / n, .y = self.y / n };
    }

    fn area(self: *const Vec2) f32 {
        return std.math.fabs(self.x * self.y);
    }

    pub fn format(
        self: Vec2,
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

    pub fn angle(self: *const Vec2) f32 {
        return std.math.atan2(f32, self.y, self.x);
    }

    pub fn min(self: *const Vec2, v: Vec2) Vec2 {
        return .{ .x = std.math.min(self.x, v.x), .y = std.math.min(self.y, v.y) };
    }

    pub fn max(self: *const Vec2, v: Vec2) Vec2 {
        return .{ .x = std.math.max(self.x, v.x), .y = std.math.max(self.y, v.y) };
    }
};

pub const Rect = struct {
    a: Vec2,
    b: Vec2,

    pub fn init(x1: f32, y1: f32, x2: f32, y2: f32) Rect {
        return .{ .a = .{ .x = x1, .y = y1 }, .b = .{ .x = x2, .y = y2 } };
    }

    pub fn centered(c: Vec2, aSize: Vec2) Rect {
        const s2 = aSize.mul(1.0 / 2.0);
        return .{ .a = c.minus(s2), .b = c.add(s2) };
    }

    pub fn sized(o: Vec2, aSize: Vec2) Rect {
        return .{ .a = o, .b = o.add(aSize) };
    }

    pub fn intersects(self: *const Rect, other: Rect) bool {
        // ((X,Y),(A,B)) and ((X1,Y1),(A1,B1))
        // (X,Y) = (self.a.x, self.a.y)
        // (A,B) = (self.b.x, self.b.y)
        // (X1,Y1) = (other.a.x, other.a.y)
        // (A1,B1) = (other.b.x, other.b.y)
        // A<X1 or A1<X or B<Y1 or B1<Y
        if ((self.b.x < other.a.x) or (other.b.x < self.a.x) or (self.b.y < other.a.y) or (other.b.y < self.a.y)) {
            return false;
        }
        return true;
    }

    pub fn size(self: *const Rect) Vec2 {
        return self.b.minus(self.a);
    }

    pub fn center(self: *const Rect) Vec2 {
        return self.a.add(self.size().mul(1.0 / 2.0));
    }

    pub fn translate(self: *const Rect, v: Vec2) Rect {
        return .{ .a = self.a.add(v), .b = self.b.add(v) };
    }

    pub fn height(self: *const Rect) f32 {
        return self.b.y - self.a.y;
    }

    fn contains(self: *const Rect, v: Vec2) bool {
        return v.x >= self.a.x and v.x <= self.b.x and v.y >= self.a.y and v.y <= self.b.y;
    }

    // union is taken
    pub fn add(self: *const Rect, r: Rect) Rect {
        return .{ .a = self.a.min(r.a), .b = self.b.max(r.b) };
    }

    pub fn area(self: *const Rect) f32 {
        return self.size().area();
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
