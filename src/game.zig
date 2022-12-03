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
const Vec = geom.Vec2;
const Rect = geom.Rect;

const Health = struct {
    maxHealth: u32,
    health: u32,
};

const Tower = struct {
    range: f32,
    fireDelay: u64,
    missileSpeed: f32,
    lastFire: u64 = 0,
    targetMonster: Id, // equals to itself when no monster is found.
};

const Monster = struct {
    speed: f32,
    targetTower: Id,
    price: usize,
};

const Projectile = struct {
    v: f32,
    target: Id,
};

const Mode = enum {
    SELECT,
    BUILD,
};

const UI = struct {
    engine: *engine.Engine,
    resources: *Resources,
    game: *Game,

    mode: Mode = Mode.SELECT,
    modeId: Id,
    shadowId: Id,
    moneyId: Id,
    selId: Id,

    selectedTowerId: ?Id = null,

    pub fn init(game: *Game) !@This() {
        return .{
            .game = game,
            .engine = game.engine,
            .resources = game.resources,
            .modeId = game.engine.ids.nextId(),
            .shadowId = game.engine.ids.nextId(),
            .moneyId = game.engine.ids.nextId(),
            .selId = game.engine.ids.nextId(),
        };
    }

    pub fn event(self: *@This(), e: *const sdl.Event) !void {
        switch (e.type) {
            sdl.sdl.SDL_KEYDOWN => switch (e.key.keysym.sym) {
                sdl.sdl.SDLK_b => self.mode = Mode.BUILD,
                sdl.sdl.SDLK_ESCAPE => self.mode = Mode.SELECT,
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
        // update ui text
        const mode = try std.fmt.allocPrintZ(frameAllocator, "mode: {}", .{self.mode});
        try self.engine.setText(self.modeId, mode, .{ .x = 0, .y = 0 }, engine.Alignment.LEFT, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        const money = try std.fmt.allocPrintZ(frameAllocator, "$ {}", .{self.game.money});
        try self.engine.setText(self.moneyId, money, .{ .x = 0, .y = 20 }, engine.Alignment.LEFT, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        try self.updateSelection();

        // update build shadow
        if (self.mode == Mode.BUILD) {
            try self.engine.bounds.set(self.shadowId, Rect.centered(self.engine.mousePos.grid(8, 8), .{ .x = 8, .y = 8 }));
            try self.engine.sprites.set(self.shadowId, self.resources.tower.sprite(0, 0, 0));
        } else {
            try self.engine.bounds.delete(self.shadowId);
            try self.engine.sprites.delete(self.shadowId);
        }
    }

    fn updateSelection(self: *@This()) !void {
        if (self.mode == Mode.SELECT) {
            if (self.selectedTowerId) |towerId| {
                if (self.game.towers.find(towerId)) |*tower| {
                    const pos = (try self.engine.bounds.get(towerId)).center();
                    const range = tower.*.value.range;
                    try self.engine.bounds.set(self.selId, Rect.initCentered(pos.x, pos.y, range * 2, range * 2));
                    try self.engine.sprites.set(self.selId, try sdl.drawCircle(self.engine.renderer, range));
                    return;
                }
            }
        }

        self.selectedTowerId = null;
        try self.engine.bounds.delete(self.selId);
        try self.engine.sprites.delete(self.selId);
    }
};

const MonstersTable = Table(Id, maxId, Monster);
const HealthsTable = Table(Id, maxId, Health);
const TowersTable = Table(Id, maxId, Tower);
const ProjectilesTable = Table(Id, maxId, Projectile);

pub const Game = struct {
    engine: *engine.Engine,
    resources: *Resources,

    lastTicks: u32 = 0,

    healths: HealthsTable,
    towers: TowersTable,
    monsters: MonstersTable,
    projectiles: ProjectilesTable,
    ui: UI,
    towersUpdated: bool = false,
    money: usize = 0,

    pub fn init(allocator: std.mem.Allocator, eng: *engine.Engine, resources: *Resources) !*Game {
        var game = try allocator.create(Game);
        game.* = .{
            .engine = eng,
            .resources = resources,
            .healths = try HealthsTable.init(allocator),
            .towers = try TowersTable.init(allocator),
            .monsters = try MonstersTable.init(allocator),
            .projectiles = try ProjectilesTable.init(allocator),
            .ui = try UI.init(game),
        };
        return game;
    }

    pub fn deinit(self: *Game) void {
        self.healths.deinit();
        self.monsters.deinit();
        self.towers.deinit();
        self.projectiles.deinit();
    }

    fn delete(self: *Game, id: Id) !void {
        try self.engine.bounds.delete(id);
        try self.engine.sprites.delete(id);
        try self.engine.animations.delete(id);

        try self.healths.delete(id);
        try self.monsters.delete(id);
        try self.towers.delete(id);
        try self.projectiles.delete(id);
    }

    pub fn addTower(self: *Game, pos: Vec) !void {
        const id = self.engine.ids.nextId();
        const tower = Tower{ .range = 100, .fireDelay = 500, .missileSpeed = 500, .targetMonster = id };
        try self.towers.set(id, tower);
        try self.healths.set(id, .{ .maxHealth = 100, .health = 100 });
        // todo: no animation should be necessary for tower
        try self.engine.bounds.set(id, Rect.initCentered(pos.x, pos.y, 8, 8));
        try self.engine.sprites.set(id, self.resources.tower.sprite(0, 0, 0));

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
                const tower = entry.*.value;
                const pos = (try self.engine.bounds.get(entry.*.id)).center();

                var collector: struct {
                    monsters: *MonstersTable,
                    pos: Vec,
                    closestId: Id,
                    closestDistance: f32,
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
                } = .{ .monsters = &self.monsters, .pos = pos, .closestId = entry.*.id, .closestDistance = std.math.f32_max };

                try self.engine.bounds.findIntersect(Rect.centered(pos, .{ .x = tower.range * 2, .y = tower.range * 2 }), @TypeOf(collector), &collector, @TypeOf(collector).callback);
                entry.*.value.targetMonster = collector.closestId;
            }
        }
    }

    fn updateMonsters(self: *Game, ticks: u32) !void {
        const dt = 0.001 * @intToFloat(f32, ticks - self.lastTicks);

        // update state
        var it = self.monsters.iterator();
        while (it.next()) |*entry| {
            const monster = &entry.*.value;
            const bound = try self.engine.bounds.get(entry.*.id);
            const loc = bound.center();

            if (self.towersUpdated or self.towers.find(monster.targetTower) == null) {
                // find closest tower
                // todo: make this faster

                var closestD: f32 = std.math.f32_max;
                var towerIt = self.towers.iterator();
                while (towerIt.next()) |*towerEntry| {
                    var towerLoc = (try self.engine.bounds.get(towerEntry.*.id)).center();
                    var d = loc.dist2(towerLoc);
                    if (d < closestD) {
                        monster.targetTower = towerEntry.*.id;
                        closestD = d;
                    }
                }
            }

            const targetLoc = (try self.engine.bounds.get(monster.targetTower)).center();
            const d = Vec.minus(targetLoc, loc);
            const n = d.norm();
            if (n > 1.0e-2) {
                const dn = d.scale(entry.*.value.speed * dt / n);
                try self.engine.bounds.update(entry.*.id, bound.translate(dn));
            }
        }
    }

    fn updateTowers(self: *Game, ticks: u32) !void {
        try self.updateTowerTargets();

        {
            // fire from towers
            var it = self.towers.iterator();
            while (it.next()) |entry| {
                const tower = &entry.value;
                const pos = (try self.engine.bounds.get(entry.id)).center();

                if (tower.targetMonster == entry.id or
                    ticks - tower.lastFire < tower.fireDelay)
                {
                    continue;
                }

                const target = try self.engine.bounds.get(tower.targetMonster);
                const d = pos.dist(target.center());
                if (d > tower.range) {
                    continue;
                }

                tower.lastFire = ticks;
                const id = self.engine.ids.nextId();
                try self.projectiles.set(id, .{ .target = tower.targetMonster, .v = tower.missileSpeed });
                try self.engine.bounds.set(id, Rect.initCentered(pos.x, pos.y, 8, 8));
                try self.engine.sprites.set(id, self.resources.fireballProjectile.sprite(0, 0, 90));
            }
        }
    }

    fn updateProjectiles(self: *Game, frameAllocator: std.mem.Allocator, ticks: u32) !void {
        {
            // move projectiles
            const dt = 0.001 * @intToFloat(f32, ticks - self.lastTicks);
            var toDelete = try SparseSet(Id, maxId, void).init(frameAllocator);
            defer toDelete.deinit();

            var it = self.projectiles.iterator();
            while (it.next()) |entry| {
                // std.log.debug("projection entry: {}", .{entry});
                const projectile = try self.engine.bounds.get(entry.id);
                const target = self.engine.bounds.find(entry.value.target) orelse {
                    // this projectile's target doesn't exist anymore, delete it.
                    try toDelete.set(entry.id, {});
                    continue;
                };

                const ds = entry.value.v * dt;

                const dir = target.value.a.minus(projectile.a);
                const n = dir.norm();
                if (n < ds) {
                    const monster = try self.monsters.get(entry.value.target);

                    try toDelete.set(entry.value.target, {});
                    try toDelete.set(entry.id, {});
                    self.money += monster.price;
                    continue;
                }

                const dn = dir.scale(ds / n);
                try self.engine.bounds.update(entry.id, projectile.translate(dn));
                (try self.engine.sprites.get(entry.id)).angle = dir.angle() * 360 / (2.0 * std.math.pi) - 90;
            }

            var toDeleteIt = toDelete.iterator();
            while (toDeleteIt.next()) |entry| {
                // std.log.debug("deleting: {}", .{entry.id});
                try self.delete(entry.id);
            }
        }
    }

    pub fn update(self: *Game, frameAllocator: std.mem.Allocator, ticks: u32) !void {
        if (self.lastTicks == 0) {
            self.lastTicks = ticks;
            return;
        }

        try self.updateMonsters(ticks);
        try self.updateTowers(ticks);
        try self.updateProjectiles(frameAllocator, ticks);

        try self.ui.update(frameAllocator);

        self.lastTicks = ticks;
        self.towersUpdated = false;
    }

    pub fn render(_: *Game) !void {}
};
