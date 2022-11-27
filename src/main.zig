const std = @import("std");
const table = @import("table.zig");
const geom = @import("geom.zig");
const buildOptions = @import("build_options");
const engine = @import("engine.zig");

const Table = table.Table;
const Id = engine.Id;
const maxId = engine.maxId;

const Vec2 = geom.Vec2;
const Rect = geom.Rect;

const contentDir = buildOptions.content_dir;
const SparseSet = @import("sparse_set.zig").SparseSet;

const sdlZig = @import("sdl.zig");
const sdl = sdlZig.sdl;
const checkNotNull = sdlZig.checkNotNull;
const checkInt = sdlZig.checkInt;
const Sprite = sdlZig.Sprite;
const SpriteSheet = sdlZig.SpriteSheet;


const AppError = error{
    NotImplementedError,
    ResourceError,
};

const Resources = struct {
    redDemon: SpriteSheet,
    tower: SpriteSheet,
    fireballProjectile: SpriteSheet,
    woodKeep: SpriteSheet,
    rubik20: *sdl.TTF_Font,

    fn init(renderer: *sdl.SDL_Renderer) !Resources {
        return .{
            .redDemon = try SpriteSheet.load(renderer, "res/MiniWorldSprites/Characters/Monsters/Demons/RedDemon.png", 16, 16),
            .tower = try SpriteSheet.load(renderer, "res/MiniWorldSprites/Buildings/Wood/Tower.png", 16, 16),
            .fireballProjectile = try SpriteSheet.load(renderer, "res/MiniWorldSprites/Objects/FireballProjectile.png", 16, 16),
            .woodKeep = try SpriteSheet.load(renderer, "res/MiniWorldSprites/Buildings/Wood/Keep.png", 32, 32),
            .rubik20 = try checkNotNull(sdl.TTF_Font, sdl.TTF_OpenFont("res/RubikMonoOne-Regular.ttf", 20)),
        };
    }

    fn deinit(self: *@This()) void {
        self.redDemon.deinit();
        self.tower.deinit();
        self.fireballProjectile.deinit();
        self.woodKeep.deinit();
        sdl.TTF_CloseFont(self.rubik20);
    }
};

const Statistics = struct {
    engine: *engine.Engine,
    resources: *Resources,

    lastTicks: u32 = 0,
    fpsId: Id = 0,
    monstersId: Id = 0,
    updateId: Id = 0,
    monsterUpdateId: Id = 0,
    renderId: Id = 0,

    pub fn init(self: *Statistics) !void {
        self.fpsId = self.engine.ids.nextId();
        self.monstersId = self.engine.ids.nextId();
        self.updateId = self.engine.ids.nextId();
        self.monsterUpdateId = self.engine.ids.nextId();
        self.renderId = self.engine.ids.nextId();
    }

    pub fn update(self: *Statistics, ticks: u32, frameAllocator: std.mem.Allocator, monsterCount: usize, updateDurationNs: u64, renderDuration: u64) !void {
        defer self.lastTicks = ticks;

        if (self.lastTicks == 0) {
            return;
        }

        const fps = try std.fmt.allocPrintZ(frameAllocator, "{d} fps", .{1000 / (ticks - self.lastTicks)});
        try self.engine.setText(self.fpsId, fps, .{ .x = 0, .y = 0 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        const monsters = try std.fmt.allocPrintZ(frameAllocator, "{} monsters", .{monsterCount});
        try self.engine.setText(self.monstersId, monsters, .{ .x = 0, .y = 20 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        const updateText = try std.fmt.allocPrintZ(frameAllocator, "{d:.0} ms/update", .{ @intToFloat(f64, updateDurationNs) / 1000000});
        try self.engine.setText(self.updateId, updateText, .{ .x = 0, .y = 40 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        const nsPerMonster = @intToFloat(f64, updateDurationNs) / @intToFloat(f64, monsterCount);
        const msMonsterText = try std.fmt.allocPrintZ(frameAllocator, "{e:.0} monsters/sec", .{ 1.0e9 / nsPerMonster});
        try self.engine.setText(self.monsterUpdateId, msMonsterText, .{ .x = 0, .y = 60 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        const renderText = try std.fmt.allocPrintZ(frameAllocator, "{d:.0} ms/render", .{ @intToFloat(f64, renderDuration) / 1000000});
        try self.engine.setText(self.renderId, renderText, .{ .x = 0, .y = 80 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);
    }
};

const Health = struct {
    maxHealth: u32,
    health: u32,
};

const Tower = struct {
    range: f32,
    fireDelay: u64,
    missileSpeed: f32,
    lastFire: u64 = 0,
    closestMonster: Id, // equals to itself when no monster is found.
};

const Monster = struct {
    speed: f32,
};

const Projectile = struct {
    v: f32,
    target: Id,
};

const Animation = struct {
    sheet: *SpriteSheet,
    sprites: []const SpriteSheet.Coords,
    animationDelay: u32,
    i: usize = 0,
    lastFrame: u64 = 0,
};

const Game = struct {
    const MonstersTable = Table(Id, maxId, Monster);

    displaySize: Vec2,
    engine: *engine.Engine,

    lastTicks: u32 = 0,
    lastUpdateDuration: u64 = 0,
    lastRenderDuration: u64 = 0,
    statistics: Statistics = undefined,

    view: Rect = undefined,
    resources: Resources = undefined,
    healths: Table(Id, maxId, Health) = undefined,
    towers: Table(Id, maxId, Tower) = undefined,
    monsters: MonstersTable = undefined,
    projectiles: Table(Id, maxId, Projectile) = undefined,
    sprites: Table(Id, maxId, Sprite) = undefined,
    animations: Table(Id, maxId, Animation) = undefined,

    fn init(self: *Game, allocator: std.mem.Allocator, renderer: *sdl.SDL_Renderer) !void {
        self.resources = try Resources.init(renderer);
        self.statistics = .{ .engine = self.engine, .resources = &self.resources };
        try self.statistics.init();

        self.healths = try @TypeOf(self.healths).init(allocator);
        self.towers = try @TypeOf(self.towers).init(allocator);
        self.monsters = try @TypeOf(self.monsters).init(allocator);
        self.projectiles = try @TypeOf(self.projectiles).init(allocator);
        self.sprites = try @TypeOf(self.sprites).init(allocator);
        self.animations = try @TypeOf(self.animations).init(allocator);

        // initially 1000 wide, centered on origin
        const w = 1000;
        const h = w * self.displaySize.y / self.displaySize.x;
        self.view = .{ .a = .{ .x = -w / 2, .y = -h / 2 }, .b = .{ .x = w / 2, .y = h / 2 } };

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
                    try self.monsters.add(id, .{ .speed = 5 });
                    try self.healths.add(id, .{ .maxHealth = 100, .health = 100 });
                    try self.engine.bounds.add(id, Rect.initCentered(@intToFloat(f32, i) * step, @intToFloat(f32, j) * step, 8, 8));
                    try self.animations.add(id, .{ .animationDelay = 200, .i = id % 4, .sheet = &self.resources.redDemon, .sprites = &[_]SpriteSheet.Coords{
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
            var i: i32 = -10000;
            while (i <= 10000) {
                try self.addTower(.{ .x = @intToFloat(f32, i), .y = 0 });
                i += 100;
            }
        }

        // try self.addTower(.{ .x = -50, .y = 0 });
        // try self.addTower(.{ .x = 50, .y = 0 });
        // try self.addTower(.{ .x = 0, .y = 50 });
        // try self.addTower(.{ .x = 0, .y = -50 });

        {
            const id = self.engine.ids.nextId();

            // add keep
            try self.engine.bounds.add(id, Rect.initCentered(0, 0, 16, 16));
            try self.sprites.add(id, self.resources.woodKeep.sprite(0, 0, 0));
        }
    }

    fn deinit(self: *Game) void {
        self.resources.deinit();
        self.engine.deinit();

        self.healths.deinit();
        self.monsters.deinit();
        self.towers.deinit();
        self.projectiles.deinit();
        self.sprites.deinit();
        self.animations.deinit();
    }

    fn delete(self: *Game, id: Id) !void {
        try self.engine.bounds.delete(id);
        try self.healths.delete(id);
        try self.monsters.delete(id);
        try self.towers.delete(id);
        try self.projectiles.delete(id);
        try self.sprites.delete(id);
        try self.animations.delete(id);
    }

    fn addTower(self: *Game, pos: Vec2) !void {
        const id = self.engine.ids.nextId();
        const tower = Tower{ .range = 100, .fireDelay = 200, .missileSpeed = 500, .closestMonster = id };
        try self.towers.add(id, tower);
        try self.healths.add(id, .{ .maxHealth = 100, .health = 100 });
        // todo: no animation should be necessary for tower
        try self.engine.bounds.add(id, Rect.initCentered(pos.x, pos.y, 8, 8));
        try self.sprites.add(id, self.resources.tower.sprite(0, 0, 0));

        const rangeId = self.engine.ids.nextId();
        try self.engine.bounds.add(rangeId, Rect.initCentered(pos.x, pos.y, tower.range * 2, tower.range * 2));
        try self.sprites.add(rangeId, try sdlZig.drawCircle(self.engine.renderer, tower.range));
    }

    fn event(self: *Game, evt: *const sdl.SDL_Event) void {
        const delta = self.view.height() / 10.0;
        const zoom = 1.1;

        switch (evt.type) {
            sdl.SDL_KEYDOWN => switch (evt.key.keysym.sym) {
                sdl.SDLK_UP => self.view = self.view.translate(.{ .x = 0, .y = -delta }),
                sdl.SDLK_DOWN => self.view = self.view.translate(.{ .x = 0, .y = delta }),
                sdl.SDLK_LEFT => self.view = self.view.translate(.{ .x = -delta, .y = 0 }),
                sdl.SDLK_RIGHT => self.view = self.view.translate(.{ .x = delta, .y = 0 }),
                else => {},
            },
            sdl.SDL_MOUSEWHEEL => {
                const z: f32 = if (evt.wheel.y > 0) zoom else 1.0 / zoom;
                self.view = Rect.centered(self.view.center(), self.view.size().mul(z));
            },
            else => {},
        }
    }

    fn updateClosestMonsters2(self: *Game) !void {
        {
            // update closest monsters
            var it = self.towers.iterator();
            while (it.next()) |*entry| {
                const tower = entry.*.value;
                const pos = (try self.engine.bounds.get(entry.*.id)).center();

                var collector: struct {
                    monsters: *MonstersTable,
                    pos: Vec2,
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

                entry.*.value.closestMonster = collector.closestId;
            }
        }
    }

    fn updateClosestMonsters(self: *Game) !void {
        {
            // reset closest monsters
            var it = self.towers.iterator();
            while (it.next()) |entry| {
                entry.value.closestMonster = entry.id;
                entry.value.closestMonsterDistance = std.math.floatMax(f32);
            }
        }

        {
            // update closest monsters
            var monsterIt = self.monsters.iterator();
            while (monsterIt.next()) |monsterEntry| {
                const mo = try self.engine.bounds.get(monsterEntry.id);

                var towerIt = self.towers.iterator();
                while (towerIt.next()) |*towerEntry| {
                    const to = try self.engine.bounds.get(towerEntry.*.id);
                    const d = to.a.dist(mo.a);
                    if (towerEntry.*.value.closestMonster == towerEntry.*.id or d < towerEntry.*.value.closestMonsterDistance) {
                        towerEntry.*.value.closestMonster = monsterEntry.id;
                        towerEntry.*.value.closestMonsterDistance = d;
                    }
                }
            }
        }
    }

    fn updateMonsters(self: *Game, ticks: u32) !void {
        const dt = 0.001 * @intToFloat(f32, ticks - self.lastTicks);

        const c: Vec2 = .{ .x = 0, .y = 0 };

        // update state
        var it = self.monsters.iterator();
        while (it.next()) |entry| {
            var o = try self.engine.bounds.get(entry.id);

            const d = Vec2.minus(c, o.a);
            const n = d.norm();
            if (n > 1.0e-2) {
                const dn = d.mul(entry.value.speed * dt / n);
                try self.engine.bounds.update(entry.id, o.translate(dn));
            }
        }
    }

    fn updateAnimations(self: *Game, ticks: u32) !void {
        // advance animation
        var it = self.animations.iterator();
        while (it.next()) |entry| {
            const animation = &entry.value;
            if (ticks - animation.lastFrame > animation.animationDelay) {
                animation.i = (animation.i + 1) % animation.sprites.len;
                animation.lastFrame = ticks;
            }
            const coords = animation.sprites[animation.i];
            try self.sprites.add(entry.id, animation.sheet.sprite(coords.x, coords.y, 0));
        }
    }

    fn updateTowers(self: *Game, ticks: u32) !void {
        try self.updateClosestMonsters2();

        {
            // fire from towers
            var it = self.towers.iterator();
            while (it.next()) |entry| {
                const tower = &entry.value;
                const pos = (try self.engine.bounds.get(entry.id)).center();

                if (tower.closestMonster == entry.id or
                    ticks - tower.lastFire < tower.fireDelay )
                {
                    continue;
                }

                const target = try self.engine.bounds.get(tower.closestMonster);
                const d = pos.dist(target.center());
                if (d > tower.range) {
                    continue;
                }

                tower.lastFire = ticks;
                const id = self.engine.ids.nextId();
                try self.projectiles.add(id, .{ .target = tower.closestMonster, .v = tower.missileSpeed });
                try self.engine.bounds.add(id, Rect.initCentered(
                    pos.x,
                    pos.y,
                    8,
                    8,
                ));
                try self.sprites.add(id, self.resources.fireballProjectile.sprite(0, 0, 90));
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
                (try self.sprites.get(entry.id)).angle = dir.angle() * 360 / (2.0 * std.math.pi) - 90;
            }

            var toDeleteIt = toDelete.iterator();
            while (toDeleteIt.next()) |entry| {
                // std.log.debug("deleting: {}", .{entry.id});
                try self.delete(entry.id);
            }
        }
    }

    fn update(self: *Game, frameAllocator: std.mem.Allocator, ticks: u32) !void {
        var timer = try std.time.Timer.start();
        defer {
            self.lastUpdateDuration = timer.read();
        }

        try self.statistics.update(ticks, frameAllocator, self.monsters.size(), self.lastUpdateDuration, self.lastRenderDuration);

        if (self.lastTicks == 0) {
            self.lastTicks = ticks;
            return;
        }

        try self.updateMonsters(ticks);
        try self.updateTowers(ticks);
        try self.updateProjectiles(frameAllocator, ticks);
        try self.updateAnimations(ticks);

        self.lastTicks = ticks;
    }

    fn render(self: *Game, renderer: *sdl.SDL_Renderer) !void {
        var timer = try std.time.Timer.start();
        defer {
            self.lastRenderDuration = timer.read();
        }

        try checkInt(sdl.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff));
        try checkInt(sdl.SDL_RenderClear(renderer));

        var sdlViewport: sdl.SDL_Rect = undefined;
        sdl.SDL_RenderGetViewport(renderer, &sdlViewport);

        const viewport = Rect.sized(.{ .x = @intToFloat(f32, sdlViewport.x), .y = @intToFloat(f32, sdlViewport.y) }, .{ .x = @intToFloat(f32, sdlViewport.w), .y = @intToFloat(f32, sdlViewport.h) });
        const view = self.view;

        const translation = viewport.a.minus(view.a);
        const scale = viewport.size().x / view.size().x;

        // draw sprites
        var it = self.sprites.iterator();
        while (it.next()) |entry| {
            const sprite = entry.value;
            const o = try self.engine.bounds.get(entry.id);
            if (self.view.intersects(o)) {
                const a = o.a.add(translation).mul(scale);
                const size = o.size().mul(scale);

                const destRect = sdl.SDL_Rect{
                    .x = @floatToInt(i32, a.x),
                    .y = @floatToInt(i32, a.y),
                    .w = @floatToInt(i32, size.x),
                    .h = @floatToInt(i32, size.y),
                };

                try checkInt(sdl.SDL_RenderCopyEx(renderer, sprite.texture, &sprite.src, &destRect, sprite.angle, null, sdl.SDL_FLIP_NONE));
            }
        }
 
        try self.engine.render();
    }
};

pub fn main() !void {
    std.log.info("Starting application, contentDir={s}", .{contentDir});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const leaked = gpa.deinit();
        if (leaked) @panic("Memory Leak Detected");
    }

    try checkInt(sdl.SDL_Init(sdl.SDL_INIT_VIDEO));
    defer {
        sdl.SDL_Quit();
        std.log.info("application done, exiting", .{});
    }

    var displayMode: sdl.SDL_DisplayMode = undefined;
    try checkInt(sdl.SDL_GetCurrentDisplayMode(0, &displayMode));

    const window = try checkNotNull(sdl.SDL_Window, sdl.SDL_CreateWindow("ZTD", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, displayMode.w, displayMode.h, sdl.SDL_WINDOW_SHOWN));
    defer sdl.SDL_DestroyWindow(window);

    try checkInt(sdl.SDL_SetWindowFullscreen(window, sdl.SDL_WINDOW_FULLSCREEN));

    try checkInt(sdl.TTF_Init());
    defer sdl.TTF_Quit();

    var renderer = try checkNotNull(sdl.SDL_Renderer, sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED | sdl.SDL_RENDERER_PRESENTVSYNC));
    defer sdl.SDL_DestroyRenderer(renderer);

    var eng = try engine.Engine.init(allocator, renderer);
    var game: Game = .{
        .displaySize = .{ .x = @intToFloat(f32, displayMode.w), .y = @intToFloat(f32, displayMode.h) },
        .engine = &eng,
    };
    try game.init(allocator, renderer);
    defer game.deinit();

    // main loop

    while (true) {
        if (eng.nextEvent()) |event| {
            game.event(&event);
        }
        if (!eng.running) {
            break;
        }

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const frameAllocator = arena.allocator();
        try game.update(frameAllocator, sdl.SDL_GetTicks());
        try game.render(renderer);
        sdl.SDL_RenderPresent(renderer);
    }
}
