const std = @import("std");

const geom = @import("geom.zig");
const Rect = geom.Rect;
const Vec = geom.Vec;

const Game = @import("game.zig").Game;

const sdl = @import("sdl.zig");
const data = @import("data.zig");

const RndGen = std.rand.DefaultPrng;
var rnd = RndGen.init(0);

pub fn initLevel2(game: *Game) !void {
    try game.addTower(.{ .x = 0, .y = 0 }, &data.ArcherTower);

    const firstCircleCount = 19;
    const countIncrement = 49;
    const circleCount = 64;
    const unitDistance = 30;

    var circle: usize = 0;
    var count: usize = firstCircleCount;
    while (circle < circleCount) {
        const r = @intToFloat(f32, unitDistance * count) / (2 * std.math.pi);

        var i: usize = 0;
        while (i < count) {
            const alpha = (2 * std.math.pi * @intToFloat(f32, i)) / @intToFloat(f32, count) + rnd.random().floatNorm(f32) / 10;
            const pos = Vec.initAngle(alpha).scale(r + 5 * rnd.random().floatNorm(f32));
            const unit = if (rnd.random().int(u32) % 100 == 0) &data.RedMonster else if (rnd.random().int(u32) % 10 == 0) &data.ArcherGoblin else &data.Orc;
            try game.addMonster(pos, unit);
            i += 1;
        }
        count += countIncrement;
        circle += 1;
    }
}

pub fn initLevel3(game: *Game, allocator: std.mem.Allocator) !void {
    try game.addTower(.{ .x = 0, .y = 0 }, &data.ArcherTower);

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
        var m: usize = 1;
        while (m < 100000) {
            const p = points[i];

            while (curDist < p.dist(last) and m < 100000) {
                const delta = last.dir(p).scale(curDist);
                const next = last.add(delta);
                try game.addMonster(next, switch (m % 10) {
                    0, 8 => &data.ArcherGoblin,
                    9 => &data.RedMonster,
                    else => &data.Orc,
                });
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

pub fn initLevel1(game: *Game) !void {
    {
        // monsters
        const dist: usize = 30;
        const size: usize = 316;

        var i: usize = 0;
        while (i < size) {
            var j: usize = 0;
            while (j < size) {
                try game.addMonster(.{ .x = @intToFloat(f32, i * dist + 100), .y = @intToFloat(f32, j * dist + 100) }, 
                 if (i == j) &data.RedMonster else &data.Orc);
                j += 1;
            }

            i += 1;
        }

        i = 0;
        while (i < 12) {
            var j: usize = 0;
            while (j < 12) {
                try game.addMonster(.{ .x = @intToFloat(f32, i * dist + 100 + size * dist), .y = @intToFloat(f32, j * dist + 100 + size * dist)}, &data.Orc);
                j += 1;
            }

            i += 1;
        }
    }

    try game.addTower(.{ .x = 0, .y = 0 }, &data.ArcherTower);
}

pub fn initStress1(game: *Game) !void {
    {
        var monster = data.Orc;
        monster.monster.speed = 100;

        // monsters
        const dist: f32 = 30;
        const size: usize = 700;

        var i: usize = 0;
        while (i < size) {
            var j: usize = 0;
            while (j < size) {
                try game.addMonster(.{ .x = @intToFloat(f32, i) * dist + 200, .y = @intToFloat(f32, j) * dist + 200 }, &monster);
                j += 1;
            }

            i += 1;
        }
    }

    var tower = data.MagicTower;
    tower.attack.damage = data.Orc.health.maxHealth;
    tower.attack.attackDelayMs = 25;
    tower.attack.attackType.projectile.speed = 500;
    tower.size = tower.size.scale(2);
    try game.addTower(.{ .x = 0, .y = 0 }, &tower);
}
