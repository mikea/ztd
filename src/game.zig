const std = @import("std");

const engine = @import("engine.zig");
const Id = engine.Id;
const maxId = engine.maxId;

const sdl = @import("sdl.zig");

const SparseSet = @import("sparse_set.zig").SparseSet;

const table = @import("table.zig");
const Table = table.Table;

const Resources = @import("resources.zig").Resources;

const geom = @import("geom.zig");
const Vec = geom.Vec;
const Rect = geom.Rect;

const model = @import("model.zig");

const Tower = struct {
    upgradeCost: usize,
};

const Monster = struct {
    speed: f32,
    price: usize,
};

const Projectile = struct {
    v: f32,
    damage: f32,
    target: Id,
};

const Attacker = struct {
    range: f32,
    attack: union(AttackType) {
        direct: struct {
            damage: f32,
        },
        projectile: struct {
            damage: f32,
            speed: f32,
        },
    },
    attackDelayMs: u64,
    lastAttack: u64 = 0,
    target: Id = 0, // pointer to Health record
};

const AttackType = enum { direct, projectile };

const Mode = enum {
    SELECT,
    BUILD,
};

const UI = struct {
    engine: *engine.Engine,
    resources: *Resources,
    game: *Game,

    mode: Mode = Mode.SELECT,
    textId: Id,
    shadowId: Id,
    selId: Id,

    selectedTowerId: ?Id = null,

    pub fn init(game: *Game) !@This() {
        return .{
            .game = game,
            .engine = game.engine,
            .resources = game.resources,
            .textId = game.engine.ids.nextId(),
            .shadowId = game.engine.ids.nextId(),
            .selId = game.engine.ids.nextId(),
        };
    }

    pub fn event(self: *@This(), e: *const sdl.Event) !void {
        switch (e.type) {
            sdl.sdl.SDL_KEYDOWN => switch (e.key.keysym.sym) {
                sdl.sdl.SDLK_b => self.mode = Mode.BUILD,
                sdl.sdl.SDLK_ESCAPE => {
                    self.mode = Mode.SELECT;
                    self.selectedTowerId = null;
                },
                sdl.sdl.SDLK_1 => {
                    if (self.mode != Mode.SELECT) return;
                    if (self.selectedTowerId) |towerId| {
                        if (self.game.towers.find(towerId)) |tower| {
                            const upgradeCost = tower.*.upgradeCost;
                            if (self.game.money >= upgradeCost) {
                                self.game.money -= upgradeCost;
                                tower.*.upgradeCost = @floatToInt(usize, @round(@intToFloat(f32, upgradeCost) * 1.5));
                                const attacker = try self.game.attackers.get(towerId);
                                attacker.*.attackDelayMs = @floatToInt(usize, @round(@intToFloat(f32, attacker.*.attackDelayMs) / 1.2));
                            }
                        }
                    }
                },
                else => {},
            },
            sdl.sdl.SDL_MOUSEBUTTONDOWN => {
                switch (self.mode) {
                    Mode.BUILD => if (self.game.money >= 10) {
                        self.mode = Mode.SELECT;
                        self.selectedTowerId = null;
                        try self.game.addTower(self.engine.mousePos.grid(8, 8));
                        self.game.money -= 10;
                    },
                    Mode.SELECT => {
                        var towerFinder: struct {
                            towers: *TowersTable,
                            towerId: ?Id = null,

                            pub fn callback(s: *@This(), id: Id, _: Rect) error{OutOfMemory}!void {
                                if (s.towers.find(id) != null) {
                                    s.towerId = id;
                                }
                            }
                        } = .{
                            .towers = &self.game.towers,
                        };

                        try self.engine.bounds.findPoint(self.engine.mousePos, @TypeOf(towerFinder), &towerFinder, @TypeOf(towerFinder).callback);
                        self.selectedTowerId = towerFinder.towerId;
                    },
                }
            },
            else => {},
        }
    }

    fn update(self: *@This(), frameAllocator: std.mem.Allocator) !void {
        const selectedTower = try self.updateSelection();

        // update ui text
        const commonText = try std.fmt.allocPrintZ(frameAllocator, "mode: {}\n$ {}", .{ self.mode, self.game.money });

        const text = switch (self.mode) {
            Mode.BUILD => commonText,
            Mode.SELECT => if (selectedTower) |tower|
                try std.fmt.allocPrintZ(frameAllocator, "{s}\n1 - upgrade rate $ {}", .{ commonText, tower.upgradeCost })
            else
                commonText,
        };
        try self.engine.setText(self.textId, text, .{ .x = 0, .y = 0 }, engine.Alignment.LEFT, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        // update build shadow
        if (self.mode == Mode.BUILD) {
            try self.engine.bounds.set(self.shadowId, Rect.centered(self.engine.mousePos.grid(8, 8), .{ .x = 8, .y = 8 }));
            try self.engine.sprites.set(self.shadowId, self.resources.tower.sprite(0, 0, 0));
        } else {
            try self.engine.bounds.delete(self.shadowId);
            try self.engine.sprites.delete(self.shadowId);
        }
    }

    fn updateSelection(self: *@This()) !?*Tower {
        if (self.mode == Mode.SELECT) {
            if (self.selectedTowerId) |towerId| {
                if (self.game.towers.find(towerId)) |tower| {
                    const pos = (try self.engine.bounds.get(towerId)).center();
                    const attacker = try self.game.attackers.get(towerId);
                    const range = attacker.range;
                    try self.engine.bounds.set(self.selId, Rect.initCentered(pos.x, pos.y, range * 2, range * 2));
                    try self.engine.sprites.set(self.selId, try sdl.drawCircle(self.engine.renderer, range));
                    return tower;
                }
            }
        }

        self.selectedTowerId = null;
        try self.engine.bounds.delete(self.selId);
        try self.engine.sprites.delete(self.selId);
        return null;
    }
};

const AttackersTable = Table(Id, maxId, Attacker);
const MonstersTable = Table(Id, maxId, Monster);
const TowersTable = Table(Id, maxId, Tower);
const ProjectilesTable = Table(Id, maxId, Projectile);

pub const Game = struct {
    engine: *engine.Engine,
    resources: *Resources,

    lastTicks: u32 = 0,

    attackers: AttackersTable,
    projectiles: ProjectilesTable,
    towers: TowersTable,

    monsters: MonstersTable,

    ui: UI,
    towersUpdated: bool = false,
    money: usize = 0,

    pub fn init(allocator: std.mem.Allocator, eng: *engine.Engine, resources: *Resources) !*Game {
        var game = try allocator.create(Game);
        game.* = .{
            .engine = eng,
            .resources = resources,
            .attackers = try AttackersTable.init(allocator),
            .towers = try TowersTable.init(allocator),
            .monsters = try MonstersTable.init(allocator),
            .projectiles = try ProjectilesTable.init(allocator),
            .ui = try UI.init(game),
        };
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

    pub fn addTower(self: *Game, pos: Vec) !void {
        const id = self.engine.ids.nextId();
        const tower = Tower{
            .upgradeCost = 10,
        };
        try self.towers.set(id, tower);
        try self.attackers.set(id, .{ .target = 0, .range = 100, .attackDelayMs = 200, .attack = .{ .projectile = .{ .damage = 90, .speed = 400 } } });
        try self.engine.bounds.set(id, Rect.initCentered(pos.x, pos.y, 8, 8));
        try self.engine.sprites.set(id, self.resources.tower.sprite(0, 0, 0));
        try self.engine.healths.set(id, .{ .maxHealth = 100, .health = 100 });

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
            const d = Vec.minus(targetLoc, loc);
            const range = d.norm();
            if (range > attacker.*.range) {
                const ds = std.math.min(attacker.*.range, entry.*.value.speed * dt);
                const dn = d.scale(ds / range);
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
                        try self.projectiles.set(id, .{ .target = attacker.target, .v = projectile.speed, .damage =  projectile.damage });
                        try self.engine.bounds.set(id, Rect.initCentered(pos.x, pos.y, 8, 8));
                        try self.engine.sprites.set(id, self.resources.fireballProjectile.sprite(0, 0, 90));
                    }
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
            std.debug.print("YOU LOST!!!!\n", .{});
            std.c.exit(0);
        }

        self.lastTicks = ticks;
        self.towersUpdated = false;
    }

    pub fn render(_: *Game) !void {}
};
