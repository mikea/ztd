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

    pub fn dist2(from: Vec2, to: Vec2) f32 {
        return minus(to, from).norm2();
    }

    pub fn dir(from: Vec2, to: Vec2) Vec2 {
        return minus(to, from).normalized();
    }

    pub fn ratio(v1: Vec2, v2: Vec2) Vec2 {
        return .{ .x = v1.x / v2.x, .y = v1.y / v2.y };
    }

    pub fn mul(v1: Vec2, v2: Vec2) Vec2 {
        return .{ .x = v1.x * v2.x, .y = v1.y * v2.y };
    }

    pub fn scale(self: *const Vec2, a: f32) Vec2 {
        return .{ .x = self.x * a, .y = self.y * a };
    }

    pub fn norm(self: *const Vec2) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn norm2(self: *const Vec2) f32 {
        return self.x * self.x + self.y * self.y;
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

    pub fn grid(self: *const Vec2, gridX: f32, gridY: f32) Vec2 {
        return .{ .x = gridX * @floor(self.x / gridX), .y = gridY * @floor(self.y / gridY) };
    }
};

pub const Rect = struct {
    a: Vec2,
    b: Vec2,

    pub fn init(x1: f32, y1: f32, x2: f32, y2: f32) Rect {
        return .{ .a = .{ .x = x1, .y = y1 }, .b = .{ .x = x2, .y = y2 } };
    }

    pub fn initCentered(x: f32, y: f32, w: f32, h: f32) Rect {
        const w2 = w / 2;
        const h2 = h / 2;
        return .{ .a = .{ .x = x - w2, .y = y - h2 }, .b = .{ .x = x + w2, .y = y + h2 } };
    }

    pub fn centered(c: Vec2, aSize: Vec2) Rect {
        const s2 = aSize.scale(1.0 / 2.0);
        return .{ .a = c.minus(s2), .b = c.add(s2) };
    }

    pub fn initSized(o: Vec2, aSize: Vec2) Rect {
        return .{ .a = o, .b = o.add(aSize) };
    }

    pub fn intersects(r1: Rect, r2: Rect) bool {
        // ((X,Y),(A,B)) and ((X1,Y1),(A1,B1))
        // (X,Y) = (r1.a.x, r1.a.y)
        // (A,B) = (r1.b.x, r1.b.y)
        // (X1,Y1) = (r2.a.x, r2.a.y)
        // (A1,B1) = (r2.b.x, r2.b.y)
        // A<X1 or A1<X or B<Y1 or B1<Y
        if ((r1.b.x < r2.a.x) or (r2.b.x < r1.a.x) or (r1.b.y < r2.a.y) or (r2.b.y < r1.a.y)) {
            return false;
        }
        return true;
    }

    pub fn size(self: *const Rect) Vec2 {
        return self.b.minus(self.a);
    }

    pub fn center(self: *const Rect) Vec2 {
        return .{ .x = (self.a.x + self.b.x) / 2, .y = (self.a.y + self.b.y) / 2 };
    }

    pub fn translate(self: *const Rect, v: Vec2) Rect {
        return .{ .a = self.a.add(v), .b = self.b.add(v) };
    }

    pub fn height(self: *const Rect) f32 {
        return self.b.y - self.a.y;
    }

    pub fn contains(self: *const Rect, v: Vec2) bool {
        return v.x >= self.a.x and v.x <= self.b.x and v.y >= self.a.y and v.y <= self.b.y;
    }

    // union is taken
    pub fn add(self: *const Rect, r: Rect) Rect {
        return .{ .a = .{ .x = std.math.min(self.a.x, r.a.x), .y = std.math.min(self.a.y, r.a.y) }, .b = .{ .x = std.math.max(self.b.x, r.b.x), .y = std.math.max(self.b.y, r.b.y) } };
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
