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
};

const Projectile = struct {
    v: f32,
    target: Id,
};

pub const Game = struct {
    const MonstersTable = Table(Id, maxId, Monster);

    engine: *engine.Engine,

    lastTicks: u32 = 0,

    resources: Resources = undefined,
    healths: Table(Id, maxId, Health) = undefined,
    towers: Table(Id, maxId, Tower) = undefined,
    monsters: MonstersTable = undefined,
    projectiles: Table(Id, maxId, Projectile) = undefined,

    pub fn init(self: *Game, allocator: std.mem.Allocator, renderer: *sdl.Renderer) !void {
        self.resources = try Resources.init(renderer);

        self.healths = try @TypeOf(self.healths).init(allocator);
        self.towers = try @TypeOf(self.towers).init(allocator);
        self.monsters = try @TypeOf(self.monsters).init(allocator);
        self.projectiles = try @TypeOf(self.projectiles).init(allocator);

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
                    const id = self.engine.ids.nextId();
                    try self.monsters.add(id, .{ .speed = 5, .targetTower = id });
                    try self.healths.add(id, .{ .maxHealth = 100, .health = 100 });
                    try self.engine.bounds.add(id, Rect.initCentered(@intToFloat(f32, i) * step, @intToFloat(f32, j) * step, 8, 8));
                    try self.engine.animations.add(id, .{ .animationDelay = 200, .i = id % 4, .sheet = &self.resources.redDemon, .sprites = &[_]sdl.SpriteSheet.Coords{
                        .{ .x = 2, .y = 0 },
                        .{ .x = 3, .y = 0 },
                        .{ .x = 4, .y = 0 },
                        .{ .x = 3, .y = 0 },
                    } });
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

    pub fn deinit(self: *Game) void {
        self.resources.deinit();

        self.healths.deinit();
        self.monsters.deinit();
        self.towers.deinit();
        self.projectiles.deinit();
        self.engine.sprites.deinit();
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

    fn addTower(self: *Game, pos: Vec) !void {
        const id = self.engine.ids.nextId();
        const tower = Tower{ .range = 100, .fireDelay = 500, .missileSpeed = 500, .targetMonster = id };
        try self.towers.add(id, tower);
        try self.healths.add(id, .{ .maxHealth = 100, .health = 100 });
        // todo: no animation should be necessary for tower
        try self.engine.bounds.add(id, Rect.initCentered(pos.x, pos.y, 8, 8));
        try self.engine.sprites.add(id, self.resources.tower.sprite(0, 0, 0));

        const rangeId = self.engine.ids.nextId();
        try self.engine.bounds.add(rangeId, Rect.initCentered(pos.x, pos.y, tower.range * 2, tower.range * 2));
        try self.engine.sprites.add(rangeId, try sdl.drawCircle(self.engine.renderer, tower.range));
    }

    pub fn event(_: *Game, _: *const sdl.Event) void {
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
                } = .{ .monsters = &self.monsters, .pos = pos, .closestId = entry.*.id, .closestDistance = std.math.f32_max};

                try self.engine.bounds.findIntersect(Rect.centered(pos, .{.x = tower.range * 2, .y = tower.range * 2}), @TypeOf(collector), &collector, @TypeOf(collector).callback);
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

            if (self.towers.find(monster.targetTower) == null) {
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
                const dn = d.mul(entry.*.value.speed * dt / n);
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
                    ticks - tower.lastFire < tower.fireDelay )
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
                try self.projectiles.add(id, .{ .target = tower.targetMonster, .v = tower.missileSpeed });
                try self.engine.bounds.add(id, Rect.initCentered(
                    pos.x,
                    pos.y,
                    8,
                    8,
                ));
                try self.engine.sprites.add(id, self.resources.fireballProjectile.sprite(0, 0, 90));
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
                    try toDelete.add(entry.id, {});
                    continue;
                };

                const ds = entry.value.v * dt;

                const dir = target.value.a.minus(projectile.a);
                const n = dir.norm();
                if (n < ds) {
                    try toDelete.add(entry.value.target, {});
                    try toDelete.add(entry.id, {});
                    continue;
                }

                const dn = dir.mul(ds / n);
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

        self.lastTicks = ticks;
    }

    pub fn render(_: *Game) !void {
    }
};
