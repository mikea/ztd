const std = @import("std");

const geom = @import("geom.zig");
const Rect = geom.Rect;
const Vec = geom.Vec2;

const Game = @import("game.zig").Game;

const sdl = @import("sdl.zig");

pub fn initLevel1(self: *Game, allocator: std.mem.Allocator) !void {
    try self.addTower(.{ .x = 0, .y = 0 });

    const points = try allocator.alloc(Vec, 20000);
    defer allocator.free(points);

    {
        // init path
        var origin = Vec{ .x = 0, .y = 0 };
        var step: f32 = std.math.pi / 20.0;
        var phi: f32 = 0.0;
        var i: usize = 0;
        while (i < points.len) {
            const r = std.math.sqrt(phi) * 100;
            const x = r * std.math.cos(phi);
            const y = r * std.math.sin(phi);
            phi += step;

            if (r < 0 or origin.dist(Vec{ .x = x, .y = y }) < 150) {
                continue;
            }

            points[i] = .{ .x = x, .y = y };
            i += 1;
        }
    }
    {
        // add monsters along the path
        const dist = 100.0;
        var i: usize = 1;

        var last = points[0];
        try addMonster(self, last);

        var curDist: f32 = dist;
        while (i < points.len) {
            const p = points[i];

            while (curDist < p.dist(last)) {
                const delta = last.dir(p).scale(curDist);
                const next = last.add(delta);
                try addMonster(self, next);

                last = next;
                curDist = dist;
            }

            curDist -= p.dist(last);
            last = p;
            i += 1;
        }
    }
}

fn addMonster(self: *Game, pos: Vec) !void {
    const id = self.engine.ids.nextId();
    try self.monsters.add(id, .{ .speed = 10, .targetTower = id, .price = 1 });
    try self.healths.add(id, .{ .maxHealth = 100, .health = 100 });
    try self.engine.bounds.add(id, Rect.initCentered(pos.x, pos.y, 8, 8));
    try self.engine.animations.add(id, .{ .animationDelay = 200, .i = id % 4, .sheet = &self.resources.redDemon, .sprites = &[_]sdl.SpriteSheet.Coords{
        .{ .x = 2, .y = 0 },
        .{ .x = 3, .y = 0 },
        .{ .x = 4, .y = 0 },
        .{ .x = 3, .y = 0 },
    } });
}

pub fn initStress1(self: *Game) !void {
    {
        // init monsters
        const grid = 200;
        const step = 20;

        var i: i32 = -grid + 1;
        while (i < grid) : (i += 1) {
            var j: i32 = -grid + 1;
            while (j < grid) : (j += 1) {
                if (j < 5 and j > -5) {
                    continue;
                }
                try addMonster(self, .{.x = @intToFloat(f32, i) * step, .y = @intToFloat(f32, j) * step});
            }
        }
    }

    {
        // init towers
        var i: i32 = -5000;
        while (i <= 5000) {
            try self.addTower(.{ .x = @intToFloat(f32, i), .y = 0 });
            i += 200;
        }
    }

    {
        const id = self.engine.ids.nextId();

        // add keep
        try self.engine.bounds.add(id, Rect.initCentered(0, 0, 16, 16));
        try self.engine.sprites.add(id, self.resources.woodKeep.sprite(0, 0, 0));
    }
}
