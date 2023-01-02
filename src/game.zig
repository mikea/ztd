const std = @import("std");
const engine = @import("engine.zig");
const resources = @import("resources.zig");
const data = @import("data.zig");
const ui = @import("ui.zig");
const gl = @import("gl.zig");
const truetype = @import("truetype.zig");
const builtin = @import("builtin");

const table = @import("table.zig");
const Table = table.Table;

const geom = @import("geom.zig");
const Vec = geom.Vec;
const Rect = geom.Rect;

const model = @import("model.zig");
const Id = model.Id;
const maxId = model.maxId;

const RndGen = std.rand.DefaultPrng;
var rnd = RndGen.init(0);

pub const Game = struct {
    engine: *engine.Engine,
    resources: *resources.Resources,

    lastTicks: u64 = 0,
    frame: u64 = 0,

    attackers: model.AttackersTable,
    projectiles: model.ProjectilesTable,
    towers: model.TowersTable,
    monsters: model.MonstersTable,

    ui: ui.UI = undefined,
    towersUpdated: bool = false,
    money: u64 = 10,
    towerPrice: u64 = 10,

    pub fn init(allocator: std.mem.Allocator, eng: *engine.Engine, res: *resources.Resources) !*Game {
        var game = try allocator.create(Game);
        game.* = .{
            .engine = eng,
            .resources = res,
            .attackers = try model.AttackersTable.init(allocator),
            .towers = try model.TowersTable.init(allocator),
            .monsters = try model.MonstersTable.init(allocator),
            .projectiles = try model.ProjectilesTable.init(allocator),
        };
        game.ui = try ui.UI.init(allocator, game);
        return game;
    }

    pub fn deinit(self: *Game) void {
        self.monsters.deinit();
        self.towers.deinit();
        self.projectiles.deinit();
        self.attackers.deinit();
        self.ui.deinit();
    }

    fn delete(self: *Game, id: Id) !void {
        self.attackers.delete(id);
        self.monsters.delete(id);
        self.towers.delete(id);
        self.projectiles.delete(id);
        try self.engine.delete(id);
    }

    pub fn addMonster(self: *Game, pos: Vec, d: *const data.MonsterData) !void {
        const id = self.engine.ids.nextId();
        try self.monsters.set(id, d.monster);
        try self.attackers.set(id, d.attack);
        try self.engine.healths.set(id, d.health);
        try self.engine.bounds.set(id, Rect.initCentered(pos, d.size));
        const sheet = self.resources.getSheet(d.animations.walk.sheet);
        const coords = d.animations.walk.sprites;
        const i = rnd.random().int(usize) % d.animations.walk.sprites.len;
        try self.engine.sprites.set(id, sheet.sprite(coords[i].x, coords[i].y, 0, .MONSTER));
        try self.engine.animations.set(id, .{
            .animationDelay = d.animations.walk.delay,
            .i = i,
            .sheet = sheet,
            .coords = coords,
            .z = .MONSTER,
        });
    }

    pub fn addTower(self: *Game, pos: Vec, d: *const data.TowerData) !void {
        const id = self.engine.ids.nextId();
        try self.towers.set(id, d.tower);
        try self.attackers.set(id, d.attack);
        try self.engine.healths.set(id, d.health);
        try self.engine.bounds.set(id, Rect.initCentered(pos, d.size));
        try self.engine.sprites.set(id, (self.resources.getSheet(d.sheet)).sprite(d.sprite.x, d.sprite.y, 0, .TOWER));
        self.towersUpdated = true;
    }

    fn updateTowerTargets(self: *Game) !void {
        // update closest monsters
        var it = self.towers.iterator();
        while (it.next()) |entry| {
            const pos = (self.engine.bounds.get(entry.id)).center();
            var collector: struct {
                game: *Game,
                pos: Vec,
                closestId: Id = 0,
                closestDistance2: f32 = std.math.f32_max,

                pub fn callback(s: *@This(), id: Id, rect: Rect) error{OutOfMemory}!void {
                    if (s.game.monsters.find(id) == null) {
                        return;
                    }

                    if (s.game.engine.healths.find(id)) |health| {
                        if (health.health <= health.futureDamage) {
                            return;
                        }
                    } else {
                        @panic("not expected");
                    }

                    const d2 = s.pos.dist2(rect.center());
                    if (d2 < s.closestDistance2) {
                        s.closestDistance2 = d2;
                        s.closestId = id;
                    }
                }
            } = .{ .game = self, .pos = pos };

            const attacker = self.attackers.get(entry.id);
            try self.engine.bounds.findIntersect(Rect.initCentered(pos, .{ .x = attacker.*.range * 2, .y = attacker.*.range * 2 }), @TypeOf(collector), &collector, @TypeOf(collector).callback);
            attacker.*.target = collector.closestId;
        }
    }

    fn updateMonsters(self: *Game, dt: f32) !void {
        // move monsters
        var it = self.monsters.iterator();
        while (it.next()) |entry| {
            const bound = self.engine.bounds.get(entry.id);
            const loc = bound.center();
            const attacker = self.attackers.get(entry.id);

            if (self.towersUpdated or self.towers.find(attacker.*.target) == null) {
                // find closest tower
                // todo: make this faster

                var closestD: f32 = std.math.f32_max;
                var towerIt = self.towers.iterator();
                while (towerIt.next()) |*towerEntry| {
                    var towerLoc = (self.engine.bounds.get(towerEntry.*.id)).center();
                    var d = loc.dist2(towerLoc);
                    if (d < closestD) {
                        attacker.*.target = towerEntry.*.id;
                        closestD = d;
                    }
                }
            }

            const targetLoc = (self.engine.bounds.get(attacker.*.target)).center();
            const dir = Vec.minus(targetLoc, loc);
            const range = dir.norm();
            if (range > attacker.*.range) {
                const ds = std.math.min(range - attacker.*.range, entry.value.speed * dt);
                const dn = dir.scale(ds / range);
                try self.engine.bounds.update(entry.id, bound.translate(dn));
            }
        }
    }

    fn updateTowers(self: *Game) !void {
        try self.updateTowerTargets();
    }

    fn updateAttackers(self: *Game, ticks: u64, frameAllocator: std.mem.Allocator) !void {
        var it = self.attackers.iterator();
        while (it.next()) |entry| {
            const pos = (self.engine.bounds.get(entry.id)).center();
            const attacker = entry.value;
            if (attacker.target == 0) {
                continue;
            }

            if (ticks - attacker.*.lastAttack < attacker.*.attackDelayMs) {
                continue;
            }

            const d = pos.dist2((self.engine.bounds.get(attacker.target)).center());
            if (d > attacker.range * attacker.range) {
                continue;
            }

            attacker.*.lastAttack = ticks;
            switch (attacker.attackType) {
                .direct => {
                    try self.addDamage(ticks, attacker.target, attacker.damage, .NOT_DELAYED, frameAllocator);
                },
                .splash => {
                    @panic("not implemented");
                },
                .projectile => {
                    try self.addProjectile(attacker, pos);
                },
            }
        }
    }

    fn addProjectile(self: *Game, attacker: *model.Attacker, pos: Vec) !void {
        const projectile = attacker.attackType.projectile;
        const id = self.engine.ids.nextId();
        const target = self.engine.bounds.get(attacker.target);
        const health = self.engine.healths.get(attacker.target);
        if (projectile.damageType == .direct) {
            health.*.futureDamage += attacker.damage;
        }
        const nav: model.Navigation = switch (attacker.attackType.projectile.navigation) {
            .POS => .{ .pos = target.center() },
            .FOLLOW => .{ .target = attacker.target },
        };
        const sheet = self.resources.getSheet(projectile.sheet);
        try self.projectiles.set(id, .{ .damageType = projectile.damageType, .navigation = nav, .v = projectile.speed, .damage = attacker.damage, .spriteAngleRad = sheet.angle });
        try self.engine.bounds.set(id, Rect.initCentered(pos, Vec.initInt(sheet.w, sheet.h)));
        try self.engine.sprites.set(id, sheet.sprite(0, 0, 0, .PROJECTILE));
    }

    fn updateProjectiles(self: *Game, ticks: u64, dt: f32, frameAllocator: std.mem.Allocator) !void {
        {
            // move projectiles
            var it = self.projectiles.iterator();
            while (it.next()) |entry| {
                const id = entry.id;
                const projectile = self.engine.bounds.get(id);

                const targetPos = switch (entry.value.navigation) {
                    .pos => |pos| pos,
                    .target => |targetId| if (self.engine.healths.find(targetId) != null) (self.engine.bounds.get(targetId)).center() else {
                        try self.engine.toDelete.set(id, {});
                        continue;
                    },
                };

                const ds = entry.value.v * dt;
                const dir = targetPos.minus(projectile.center());
                const dist = dir.norm();
                if (dist < ds) {
                    try self.engine.toDelete.set(id, {});
                    switch (entry.value.damageType) {
                        .direct => {
                            switch (entry.value.navigation) {
                                .target => |targetId| {
                                    try self.addDamage(ticks, targetId, entry.value.damage, .DELAYED, frameAllocator);
                                },
                                else => {
                                    @panic("splash damage without projectile not implemented");
                                },
                            }
                        },
                        .splash => |splash| {
                            try self.addSplashDamage(ticks, targetPos, splash.radius, entry.value.damage, frameAllocator);
                        },
                    }
                } else {
                    const dn = dir.scale(ds / dist);
                    const newPos = projectile.translate(dn);
                    try self.engine.bounds.update(id, newPos);
                    (self.engine.sprites.get(id)).angle = dir.angle() + entry.value.spriteAngleRad;
                }
            }
        }

        try self.updateDeleted();
    }

    fn addSplashDamage(self: *Game, ticks: u64, pos: Vec, radius: f32, damage: f32, frameAllocator: std.mem.Allocator) !void {
        {
            const num = 50 + @floatToInt(u32, 20 * rnd.random().float(f32));
            const duration = 150;
            var i: u32 = 0;
            while (i < num) {
                const angle: f32 = 2 * std.math.pi * rnd.random().float(f32);
                const id = self.engine.ids.nextId();
                const sheet = self.resources.getSheet(.FIREBALL_PROJECTILE);
                const sprite = sheet.sprite(0, 0, angle, .PROJECTILE);

                try self.engine.bounds.set(id, Rect.initCentered(pos, Vec.initInt(sheet.w, sheet.h).scale(1.0 / 4.0)));
                try self.engine.sprites.set(id, sprite);
                try self.engine.particles.set(id, .{
                    .v = Vec.initAngle(angle).scale(radius * 1000.0 / @intToFloat(f32, duration) + rnd.random().floatNorm(f32)),
                    .startTicks = ticks,
                    .endTicks = ticks + duration,
                    .onComplete = .DO_NOTHING,
                });
                i += 1;
            }
        }

        var processor: struct {
            pos: Vec,
            radius: f32,
            damage: f32,
            game: *Game,
            monsters: std.ArrayList(Id),

            pub fn callback(s: *@This(), id: Id, r: Rect) error{OutOfMemory}!void {
                if (r.center().dist(s.pos) > s.radius) return;

                if (s.game.monsters.find(id) != null) {
                    if (s.game.engine.healths.find(id) != null) {
                        try s.monsters.append(id);
                    }
                }
            }
        } = .{
            .game = self,
            .pos = pos,
            .radius = radius,
            .damage = damage,
            .monsters = std.ArrayList(Id).init(frameAllocator),
        };

        try self.engine.bounds.findIntersect(Rect.initCentered(pos, .{ .x = radius * 2, .y = radius * 2 }), @TypeOf(processor), &processor, @TypeOf(processor).callback);
        for (processor.monsters.items) |id| {
            try self.addDamage(ticks, id, damage, .NOT_DELAYED, frameAllocator);
        }
    }

    fn addDamage(self: *Game, ticks: u64, id: Id, damage: f32, wasDelayed: enum { DELAYED, NOT_DELAYED }, frameAllocator: std.mem.Allocator) !void {
        const health = self.engine.healths.get(id);
        health.*.health -= damage;
        if (wasDelayed == .DELAYED) {
            health.*.futureDamage -= damage;
            std.debug.assert(health.futureDamage >= 0);
        }
        const text = try std.fmt.allocPrintZ(frameAllocator, "{}", .{@floatToInt(u64, damage)});
        const texture = try truetype.renderText(text, 8, frameAllocator);

        const bounds = self.engine.bounds.get(id);
        const pos = bounds.center();
        const damageId = self.engine.ids.nextId();

        try self.engine.bounds.set(damageId, Rect.initCentered(pos, Vec.initInt(texture.w, texture.h).scale(1)));
        try self.engine.sprites.set(damageId, .{
            .texture = texture.texture,
            .rect = Rect.initInt(0, 0, 1, 1),
            .angle = 0,
            .z = .DAMAGE,
        });
        try self.engine.particles.set(damageId, .{
            .startTicks = ticks,
            .v = .{ .x = 0, .y = 20 + rnd.random().floatNorm(f32) },
            .endTicks = ticks + 400,
            .onComplete = .FREE_TEXTURE,
        });
    }

    fn updateDead(self: *Game, ticks: u64, frameAllocator: std.mem.Allocator) !void {
        // remove 0 health
        var it = self.engine.healths.iterator();
        while (it.next()) |entry| {
            if (entry.value.health <= 0) {
                try self.engine.toDelete.set(entry.id, {});
                if (self.monsters.find(entry.id)) |monster| {
                    self.money += monster.*.price;

                    const text = try std.fmt.allocPrintZ(frameAllocator, "{}", .{monster.*.price});
                    // const texture = try sdl.renderText(self.engine.renderer, text, self.resources.rubik8, .{ .r = 255, .g = 215, .b = 0, .a = 255 });
                    // const bounds = self.engine.bounds.get(entry.id);
                    // const pos = bounds.center();
                    // const textId = self.engine.ids.nextId();

                    // try self.engine.bounds.set(textId, Rect.centered(pos, Vec.initInt(texture.w, texture.h)));
                    // try self.engine.sprites.set(textId, .{
                    //     .texture = texture.texture,
                    //     .src = .{ .x = 0, .y = 0, .w = texture.w, .h = texture.h },
                    //     .angleRad = 0,
                    //     .z = .DAMAGE,
                    // });
                    // try self.engine.particles.set(textId, .{
                    //     .startTicks = ticks,
                    //     .v = .{ .x = 0, .y = -15 + rnd.random().floatNorm(f32) },
                    //     .endTicks = ticks + 600,
                    //     .onComplete = .FREE_TEXTURE,
                    // });
                    _ = text;
                    _ = ticks;
                    // @panic("not implemented");
                }
            }
        }
        try self.updateDeleted();
    }

    fn updateDeleted(self: *Game) !void {
        var toDeleteIt = self.engine.toDelete.iterator();
        while (toDeleteIt.next()) |entry| {
            try self.delete(entry.id);
        }

        self.engine.toDelete.clear();
    }

    pub fn update(self: *Game, frameAllocator: std.mem.Allocator, ticks: u64) !void {
        if (self.lastTicks == 0) {
            self.lastTicks = ticks;
            return;
        }
        const dt = 0.001 * @intToFloat(f32, ticks - self.lastTicks);

        try self.updateMonsters(dt);
        try self.updateTowers();
        try self.updateAttackers(ticks, frameAllocator);
        try self.updateProjectiles(ticks, dt, frameAllocator);
        try self.updateDead(ticks, frameAllocator);

        try self.engine.updateParticles(ticks, dt);
        try self.updateDeleted();

        try self.engine.updateAnimations(ticks);
        try self.updateDeleted();

        if (self.monsters.size() == 0) {
            try std.io.getStdOut().writer().print("YOU WON!!!!\n", .{});
            std.c.exit(0);
        }
        if (self.towers.size() == 0) {
            try std.io.getStdOut().writer().print("YOU LOST! {} monsters remaining\n", .{self.monsters.size()});
            std.c.exit(0);
        }

        try self.ui.update(frameAllocator);

        self.lastTicks = ticks;
        self.towersUpdated = false;
        self.frame += 1;
    }

    pub fn render(self: *Game, frameAllocator: std.mem.Allocator) !void {
        try self.ui.render(frameAllocator);
    }

    pub fn onEvent(self: *Game, event: *const gl.Event) !void {
        switch (event.*) {
            .keyPress => |keyPress| switch (keyPress.key) {
                gl.c.GLFW_KEY_Q => std.c.exit(0),
                else => {},
            },
            else => {},
        }
        try self.ui.onEvent(event);
    }
};
