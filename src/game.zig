const std = @import("std");
const engine = @import("engine.zig");
const sdl = @import("sdl.zig");
const resources = @import("resources.zig");
const data = @import("data.zig");
const ui = @import("ui.zig");

const SparseSet = @import("sparse_set.zig").SparseSet;

const table = @import("table.zig");
const Table = table.Table;

const geom = @import("geom.zig");
const Vec = geom.Vec;
const Rect = geom.Rect;

const model = @import("model.zig");
const Id = model.Id;
const maxId = model.maxId;


const Projectile = struct {
    v: f32,
    damage: f32,
    target: Id,
};

const AttackersTable = Table(Id, maxId, model.Attacker);
const MonstersTable = Table(Id, maxId, model.Monster);
pub const TowersTable = Table(Id, maxId, model.Tower);
const ProjectilesTable = Table(Id, maxId, Projectile);

pub const Game = struct {
    engine: *engine.Engine,
    resources: *resources.Resources,

    lastTicks: u32 = 0,

    attackers: AttackersTable,
    projectiles: ProjectilesTable,
    towers: TowersTable,

    monsters: MonstersTable,

    ui: ui.UI = undefined,
    towersUpdated: bool = false,
    money: usize = 0,
    towerPrice: usize = 10,

    pub fn init(allocator: std.mem.Allocator, eng: *engine.Engine, res: *resources.Resources) !*Game {
        var game = try allocator.create(Game);
        game.* = .{
            .engine = eng,
            .resources = res,
            .attackers = try AttackersTable.init(allocator),
            .towers = try TowersTable.init(allocator),
            .monsters = try MonstersTable.init(allocator),
            .projectiles = try ProjectilesTable.init(allocator),
        };
        game.ui = try ui.UI.init(game);
        return game;
    }

    pub fn deinit(self: *Game) void {
        self.monsters.deinit();
        self.towers.deinit();
        self.projectiles.deinit();
        self.attackers.deinit();
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
            .animationDelay = d.animations.walk.delay,
            .i = id % d.animations.walk.sprites.len,
            .sheet = self.resources.getSheet(d.animations.walk.sheet),
            .sprites = d.animations.walk.sprites,
        });
    }

    pub fn addTower(self: *Game, pos: Vec, d: *const data.TowerData) !void {
        const id = self.engine.ids.nextId();
        try self.towers.set(id, d.tower);
        try self.attackers.set(id, d.attack);
        try self.engine.healths.set(id, d.health);
        try self.engine.bounds.set(id, Rect.initCentered(pos.x, pos.y, d.size.x, d.size.y));
        try self.engine.sprites.set(id, (self.resources.getSheet(d.sheet)).sprite(d.sprite.x, d.sprite.y, 0));
        self.towersUpdated = true;
    }

    pub fn event(self: *Game, e: *const sdl.Event) !void {
        try self.ui.event(e);
    }

    fn updateTowerTargets(self: *Game) !void {
        {
            // update closest monsters
            var it = self.towers.iterator();
            while (it.next()) |*entry| {
                const attacker = try self.attackers.get(entry.*.id);
                const pos = (try self.engine.bounds.get(entry.*.id)).center();

                var collector: struct {
                    monsters: *MonstersTable,
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
        while (it.next()) |*entry| {
            const bound = try self.engine.bounds.get(entry.*.id);
            const loc = bound.center();
            const attacker = try self.attackers.get(entry.*.id);

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
                const ds = std.math.min(range - attacker.*.range, entry.*.value.speed * dt);
                const dn = dir.scale(ds / range);
                try self.engine.bounds.update(entry.*.id, bound.translate(dn));
            }
        }
    }

    fn updateTowers(self: *Game) !void {
        try self.updateTowerTargets();
    }

    fn updateAttackers(self: *Game, ticks: u32) !void {
        var it = self.attackers.iterator();
        while (it.next()) |*entry| {
            const pos = (try self.engine.bounds.get(entry.*.id)).center();
            const attacker = &entry.*.value;

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
                switch (attacker.attack) {
                    .direct => {
                        targetHealth.*.health -= attacker.attack.direct.damage;
                    },
                    .projectile => |*projectile| {
                        const id = self.engine.ids.nextId();
                        try self.projectiles.set(id, .{ .target = attacker.target, .v = projectile.speed, .damage = projectile.damage });
                        try self.engine.bounds.set(id, Rect.initCentered(pos.x, pos.y, 8, 8));
                        try self.engine.sprites.set(id, (self.resources.getSheet(projectile.sheet)).sprite(0, 0, 90));
                    },
                }
            }
        }
    }

    fn updateProjectiles(self: *Game, ticks: u32) !void {
        {
            // move projectiles
            const dt = 0.001 * @intToFloat(f32, ticks - self.lastTicks);

            var it = self.projectiles.iterator();
            while (it.next()) |*entry| {
                const id = entry.*.id;
                const projectile = try self.engine.bounds.get(id);

                if (self.engine.healths.find(entry.*.value.target)) |targetHealth| {
                    const target = (try self.engine.bounds.get(entry.*.value.target)).center();
                    const ds = entry.*.value.v * dt;
                    const dir = target.minus(projectile.center());
                    const n = dir.norm();
                    if (n < ds) {
                        // will self-destruct
                        entry.*.value.target = 0;
                        targetHealth.*.health -= entry.*.value.damage;
                    } else {
                        const dn = dir.scale(ds / n);
                        try self.engine.bounds.update(id, projectile.translate(dn));
                        (try self.engine.sprites.get(id)).angle = dir.angle() * 360 / (2.0 * std.math.pi) - 90;
                    }
                } else {
                    // will self-destruct
                    entry.*.value.target = 0;
                }
            }
        }
    }

    pub fn updateDead(self: *Game, frameAllocator: std.mem.Allocator) !void {
        var toDelete = try SparseSet(Id, maxId, void).init(frameAllocator);
        defer toDelete.deinit();

        {
            // remove 0 health
            var it = self.engine.healths.iterator();
            while (it.next()) |*entry| {
                if (entry.*.value.health <= 0) {
                    try toDelete.set(entry.*.id, {});
                    if (self.monsters.find(entry.*.id)) |monster| {
                        self.money += monster.*.price;
                    }
                }
            }
        }

        {
            // remove projectiles that lost their target
            var it = self.projectiles.iterator();
            while (it.next()) |*entry| {
                if (entry.*.value.target == 0) {
                    try toDelete.set(entry.*.id, {});
                }
            }
        }

        var toDeleteIt = toDelete.iterator();
        while (toDeleteIt.next()) |entry| {
            try self.delete(entry.id);
        }
    }

    pub fn update(self: *Game, frameAllocator: std.mem.Allocator, ticks: u32) !void {
        if (self.lastTicks == 0) {
            self.lastTicks = ticks;
            return;
        }

        try self.updateMonsters(ticks);
        try self.updateTowers();
        try self.updateAttackers(ticks);
        try self.updateProjectiles(ticks);
        try self.updateDead(frameAllocator);
        try self.ui.update(frameAllocator);

        if (self.monsters.size() == 0) {
            std.log.info("YOU WON!!!!\n", .{});
            std.c.exit(0);
        }

        if (self.towers.size() == 0) {
            std.debug.print("YOU LOST! {} monsters remaining\n", .{self.monsters.size()});
            std.c.exit(0);
        }

        self.lastTicks = ticks;
        self.towersUpdated = false;
    }

    pub fn render(_: *Game) !void {}
};
