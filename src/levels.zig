const std = @import("std");

const geom = @import("geom.zig");
const Rect = geom.Rect;
const Vec = geom.Vec;

const Game = @import("game.zig").Game;

const sdl = @import("sdl.zig");
const data = @import("data.zig");

pub fn initLevel1(game: *Game, allocator: std.mem.Allocator) !void {
    try game.addTower(.{ .x = 0, .y = 0 }, &data.MagicTower);

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
        try game.addMonster(last, &data.RedMonster);

        var curDist: f32 = dist;
        var m: usize = 0;
        while (i < points.len) {
            const p = points[i];

            while (curDist < p.dist(last)) {
                const delta = last.dir(p).scale(curDist);
                const next = last.add(delta);
                try game.addMonster(next, if (m % 10 != 9) &data.Orc else &data.RedMonster);
                m += 1;

                last = next;
                curDist = dist;
            }

            curDist -= p.dist(last);
            last = p;
            i += 1;
        }
    }
}

pub fn initStress1(game: *Game) !void {
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
                try game.addMonster(.{.x = @intToFloat(f32, i) * step, .y = @intToFloat(f32, j) * step}, &data.RedMonster);
            }
        }
    }

    {
        // init towers
        var i: i32 = -5000;
        while (i <= 5000) {
            try game.addTower(.{ .x = @intToFloat(f32, i), .y = 0 }, &data.MagicTower);
            i += 200;
        }
    }

    try game.addTower(.{ .x = 0, .y = 0 }, &data.Keep);
}
