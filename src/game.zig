const std = @import("std");
const engine = @import("engine.zig");
const sdl = @import("sdl.zig");
const resources = @import("resources.zig");
const data = @import("data.zig");
const ui = @import("ui.zig");

const table = @import("table.zig");
const Table = table.Table;

const geom = @import("geom.zig");
const Vec = geom.Vec;
const Rect = geom.Rect;

const model = @import("model.zig");
const Id = model.Id;
const maxId = model.maxId;

pub const Game = struct {
    engine: *engine.Engine,
    resources: *resources.Resources,

    lastTicks: u32 = 0,

    attackers: model.AttackersTable,
    projectiles: model.ProjectilesTable,
    towers: model.TowersTable,
    monsters: model.MonstersTable,

    ui: ui.UI = undefined,
    towersUpdated: bool = false,
    money: usize = 10,
    towerPrice: usize = 10,

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
        try self.attackers.delete(id);
        try self.monsters.delete(id);
        try self.towers.delete(id);
        try self.projectiles.delete(id);
        try self.engine.delete(id);
    }

    pub fn addMonster(self: *Game, pos: Vec, d: *const data.MonsterData) !void {
        const id = self.engine.ids.nextId();
        try self.monsters.set(id, d.monster);
        try self.attackers.set(id, d.attack);
        try self.engine.healths.set(id, d.health);
        try self.engine.bounds.set(id, Rect.initCentered(pos.x, pos.y, d.size.x, d.size.y));
        try self.engine.animations.set(id, .{
            .sprites = .{
                .animationDelay = d.animations.walk.delay,
                .i = id % d.animations.walk.sprites.len,
                .sheet = self.resources.getSheet(d.animations.walk.sheet),
                .coords = d.animations.walk.sprites,
                .z = .MONSTER,
            },
        });
    }

    pub fn addTower(self: *Game, pos: Vec, d: *const data.TowerData) !void {
        const id = self.engine.ids.nextId();
        try self.towers.set(id, d.tower);
        try self.attackers.set(id, d.attack);
        try self.engine.healths.set(id, d.health);
        try self.engine.bounds.set(id, Rect.initCentered(pos.x, pos.y, d.size.x, d.size.y));
        try self.engine.sprites.set(id, (self.resources.getSheet(d.sheet)).sprite(d.sprite.x, d.sprite.y, 0, .TOWER));
        self.towersUpdated = true;
    }

    pub fn event(self: *Game, e: *const sdl.Event) !void {
        try self.ui.event(e);
    }

    fn updateTowerTargets(self: *Game) !void {
        {
            // update closest monsters
            var it = self.towers.iterator();
            while (it.next()) |entry| {
                const attacker = try self.attackers.get(entry.id);
                const pos = (try self.engine.bounds.get(entry.id)).center();

                var collector: struct {
                    monsters: *model.MonstersTable,
                    pos: Vec,
                    closestId: Id = 0,
                    closestDistance: f32 = std.math.f32_max,
                    iter: usize = 0,

                    pub fn callback(s: *@This(), id: Id, rect: Rect) error{OutOfMemory}!void {
                        if (s.monsters.find(id) == null) {
                            return;
                        }

                        s.iter += 1;
                        const d = s.pos.dist(rect.center());
                        if (d < s.closestDistance) {
                            s.closestDistance = d;
                            s.closestId = id;
                        }
                    }
                } = .{ .monsters = &self.monsters, .pos = pos };

                try self.engine.bounds.findIntersect(Rect.centered(pos, .{ .x = attacker.*.range * 2, .y = attacker.*.range * 2 }), @TypeOf(collector), &collector, @TypeOf(collector).callback);
                attacker.*.target = collector.closestId;
            }
        }
    }

    fn updateMonsters(self: *Game, ticks: u32) !void {
        const dt = 0.001 * @intToFloat(f32, ticks - self.lastTicks);

        // move monsters
        var it = self.monsters.iterator();
        while (it.next()) |entry| {
            const bound = try self.engine.bounds.get(entry.id);
            const loc = bound.center();
            const attacker = try self.attackers.get(entry.id);

            if (self.towersUpdated or self.towers.find(attacker.*.target) == null) {
                // find closest tower
                // todo: make this faster

                var closestD: f32 = std.math.f32_max;
                var towerIt = self.towers.iterator();
                while (towerIt.next()) |*towerEntry| {
                    var towerLoc = (try self.engine.bounds.get(towerEntry.*.id)).center();
                    var d = loc.dist2(towerLoc);
                    if (d < closestD) {
                        attacker.*.target = towerEntry.*.id;
                        closestD = d;
                    }
                }
            }

            const targetLoc = (try self.engine.bounds.get(attacker.*.target)).center();
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

    fn updateAttackers(self: *Game, ticks: u32) !void {
        var it = self.attackers.iterator();
        while (it.next()) |entry| {
            const pos = (try self.engine.bounds.get(entry.id)).center();
            const attacker = entry.value;

            if (ticks - attacker.*.lastAttack < attacker.*.attackDelayMs) {
                continue;
            }

            if (self.engine.healths.find(attacker.target)) |targetHealth| {
                const target = try self.engine.bounds.get(attacker.target);
                const d = pos.dist(target.center());
                if (d > attacker.range) {
                    continue;
                }

                attacker.*.lastAttack = ticks;
                switch (attacker.attackType) {
                    .direct => {
                        targetHealth.*.health -= attacker.damage;
                    },
                    .splash => {
                        @panic("not implemented");
                    },
                    .projectile => |*projectile| {
                        const id = self.engine.ids.nextId();
                        const nav: model.Navigation = switch (projectile.navigation) {
                            .POS => .{ .pos = target.center() },
                            .FOLLOW => .{ .target = attacker.target },
                        };
                        try self.projectiles.set(id, .{ .damageType = projectile.damageType, .navigation = nav, .v = projectile.speed, .damage = attacker.damage });
                        try self.engine.bounds.set(id, Rect.initCentered(pos.x, pos.y, 8, 8));
                        try self.engine.sprites.set(id, (self.resources.getSheet(projectile.sheet)).sprite(0, 0, 90, .PROJECTILE));
                    },
                }
            }
        }
    }

    fn updateProjectiles(self: *Game, ticks: u32, frameAllocator: std.mem.Allocator) !void {
        {
            // move projectiles
            const dt = 0.001 * @intToFloat(f32, ticks - self.lastTicks);

            var it = self.projectiles.iterator();
            while (it.next()) |entry| {
                const id = entry.id;
                const projectile = try self.engine.bounds.get(id);

                const targetPos = switch (entry.value.navigation) {
                    .pos => |pos| pos,
                    .target => |targetId| if (self.engine.healths.find(targetId) != null) (try self.engine.bounds.get(targetId)).center() else {
                        try self.engine.toDelete.set(id, {});
                        continue;
                    },
                };

                const ds = entry.value.v * dt;
                const dir = targetPos.minus(projectile.center());
                const n = dir.norm();
                if (n < ds) {
                    try self.engine.toDelete.set(id, {});
                    switch (entry.value.damageType) {
                        .direct => {
                            switch (entry.value.navigation) {
                                .target => |targetId| {
                                    try self.addDamage(targetId, entry.value.damage, ticks, frameAllocator);
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
                    const dn = dir.scale(ds / n);
                    try self.engine.bounds.update(id, projectile.translate(dn));
                    (try self.engine.sprites.get(id)).angle = dir.angle() * 360 / (2.0 * std.math.pi) - 90;
                }
            }
        }
    }

    fn addSplashDamage(self: *Game, ticks: usize, pos: Vec, radius: f32, damage: f32, frameAllocator: std.mem.Allocator) !void {
        const i = self.engine.ids.nextId();
        try self.engine.bounds.set(i, Rect.initCentered(pos.x, pos.y, radius * 2, radius * 2));
        const c = try sdl.drawCircle(self.engine.renderer, radius, .{ .r = 1, .g = 0, .b = 0, .a = 0.5 }, .fill);
        try self.engine.sprites.set(i, .{ .texture = c.texture, .src = .{ .x = 0, .y = 0, .w = c.w, .h = c.h }, .angle = 0, .z = .SPLASH_DAMAGE });
        try self.engine.animations.set(i, .{
            .timed = .{ .endTicks = ticks + 300, .onComplete = .FREE_TEXTURE },
        });

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

        try self.engine.bounds.findIntersect(Rect.initCentered(pos.x, pos.y, radius * 2, radius * 2), @TypeOf(processor), &processor, @TypeOf(processor).callback);
        for (processor.monsters.items) |id| {
            try self.addDamage(id, damage, ticks, frameAllocator);
        }
    }

    fn addDamage(self: *Game, id: Id, damage: f32, ticks: usize, frameAllocator: std.mem.Allocator) !void {
        if (self.engine.healths.find(id)) |*health| {
            health.*.health -= damage;

            const text = try std.fmt.allocPrintZ(frameAllocator, "{}", .{@floatToInt(i64, damage)});
            const texture = try sdl.renderText(self.engine.renderer, text, self.resources.rubik20, .{ .r = 255, .g = 0, .b = 0, .a = 255 });
            const bounds = try self.engine.bounds.get(id);
            const pos = bounds.center();
            const damageId = self.engine.ids.nextId();

            try self.engine.bounds.set(damageId, Rect.centered(pos, Vec.initInt(texture.w >> 3, texture.h >> 3)));
            try self.engine.sprites.set(damageId, .{
                .texture = texture.texture,
                .src = .{ .x = 0, .y = 0, .w = texture.w, .h = texture.h },
                .angle = 0,
                .z = .DAMAGE,
            });
            try self.engine.animations.set(damageId, .{.timed = .{.endTicks = ticks + 300, .onComplete = .FREE_TEXTURE }});
        }
    }

    fn updateDead(self: *Game) !void {
        // remove 0 health
        var it = self.engine.healths.iterator();
        while (it.next()) |entry| {
            if (entry.value.health <= 0) {
                try self.engine.toDelete.set(entry.id, {});
                if (self.monsters.find(entry.id)) |monster| {
                    self.money += monster.*.price;
                }
            }
        }
    }

    fn updateDeleted(self: *Game) !void {
        var toDeleteIt = self.engine.toDelete.iterator();
        while (toDeleteIt.next()) |entry| {
            try self.delete(entry.id);
        }

        self.engine.toDelete.clear();
    }

    pub fn update(self: *Game, frameAllocator: std.mem.Allocator, ticks: u32) !void {
        if (self.lastTicks == 0) {
            self.lastTicks = ticks;
            return;
        }

        try self.updateMonsters(ticks);
        try self.updateTowers();
        try self.updateAttackers(ticks);

        try self.updateProjectiles(ticks, frameAllocator);
        try self.updateDeleted();

        try self.updateDead();
        try self.updateDeleted();

        try self.engine.updateAnimations(ticks);
        try self.updateDeleted();

        if (self.monsters.size() == 0) {
            std.log.info("YOU WON!!!!\n", .{});
            std.c.exit(0);
        }
        if (self.towers.size() == 0) {
            std.debug.print("YOU LOST! {} monsters remaining\n", .{self.monsters.size()});
            std.c.exit(0);
        }

        try self.ui.update(frameAllocator);

        self.lastTicks = ticks;
        self.towersUpdated = false;
    }

    pub fn render(_: *Game) !void {}
};
