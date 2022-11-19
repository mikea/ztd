const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL2/SDL_ttf.h");
});
const table = @import("table.zig");
const buildOptions = @import("build_options");

const Table = table.Table;
const Id = table.Id;
const maxId = table.maxId;

const contentDir = buildOptions.content_dir;
const SparseSet = @import("sparse_set.zig").SparseSet;

const AppError = error{
    SdlInitError,
    NotImplementedError,
    SdlError,
    ResourceError,
};

fn checkInt(i: c_int) !void {
    if (i < 0) {
        return AppError.SdlInitError;
    }
}

fn checkNotNull(comptime T: type, ptr: ?*T) !*T {
    return ptr orelse AppError.SdlInitError;
}

const Vec2 = struct {
    x: f32,
    y: f32,

    fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    fn minus(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    fn dist(from: Vec2, to: Vec2) f32 {
        return minus(to, from).norm();
    }

    fn dir(from: Vec2, to: Vec2) Vec2 {
        return minus(to, from).normalized();
    }

    fn mul(self: *const Vec2, a: f32) Vec2 {
        return .{ .x = self.x * a, .y = self.y * a };
    }

    fn norm(self: *const Vec2) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    fn normalized(self: *const Vec2) Vec2 {
        const n = self.norm();
        return .{ .x = self.x / n, .y = self.y / n };
    }

    pub fn format(
        self: Vec2,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("({},{})", .{
            self.x,
            self.y,
        });
    }
};

const Rect = struct {
    a: Vec2,
    b: Vec2,

    fn centered(c: Vec2, aSize: Vec2) Rect {
        const s2 = aSize.mul(1.0 / 2.0);
        return .{ .a = c.minus(s2), .b = c.add(s2) };
    }

    fn sized(o: Vec2, aSize: Vec2) Rect {
        return .{ .a = o, .b = o.add(aSize) };
    }

    fn intersects(self: *const Rect, other: Rect) bool {
        // ((X,Y),(A,B)) and ((X1,Y1),(A1,B1))
        // (X,Y) = (self.a.x, self.a.y)
        // (A,B) = (self.b.x, self.b.y)
        // (X1,Y1) = (other.a.x, other.a.y)
        // (A1,B1) = (other.b.x, other.b.y)
        // A<X1 or A1<X or B<Y1 or B1<Y
        if ((self.b.x < other.a.x) or (other.b.x < self.a.x) or (self.b.y < other.a.y) or (other.b.y < self.a.y)) {
            return false;
        }
        return true;
    }

    fn size(self: *const Rect) Vec2 {
        return self.b.minus(self.a);
    }

    fn center(self: *const Rect) Vec2 {
        return self.a.add(self.size().mul(1.0 / 2.0));
    }

    fn translate(self: *const Rect, v: Vec2) Rect {
        return .{ .a = self.a.add(v), .b = self.b.add(v) };
    }

    fn height(self: *const Rect) f32 {
        return self.b.y - self.a.y;
    }

    fn contains(self: *const Rect, v: Vec2) bool {
        return v.x >= self.a.x and v.x <= self.b.x and v.y >= self.a.y and v.y <= self.b.y;
    }

    pub fn format(
        self: Rect,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("[{},{}]", .{
            self.a,
            self.b,
        });
    }
};

// -- table and things

const SpriteSheet = struct {
    texture: *sdl.SDL_Texture,
    w: u16,
    h: u16,

    fn load(renderer: *sdl.SDL_Renderer, file: [*:0]const u8, w: u16, h: u16) !SpriteSheet {
        const texture = try checkNotNull(sdl.SDL_Texture, sdl.IMG_LoadTexture(renderer, file));
        return .{ .texture = texture, .w = w, .h = h };
    }

    fn deinit(self: *@This()) void {
        sdl.SDL_DestroyTexture(self.texture);
    }

    const Coords = struct {
        x: u16,
        y: u16,
    };

    fn sprite(self: *@This(), x: u16, y: u16) Sprite {
        return .{ .texture = self.texture, .src = sdl.SDL_Rect{
            .x = x * self.w,
            .y = y * self.h,
            .w = self.w,
            .h = self.h,
        } };
    }
};

const Resources = struct {
    redDemon: SpriteSheet,
    tower: SpriteSheet,
    fireballProjectile: SpriteSheet,

    fn init(renderer: *sdl.SDL_Renderer) !Resources {
        return .{
            .redDemon = try SpriteSheet.load(renderer, "res/MiniWorldSprites/Characters/Monsters/Demons/RedDemon.png", 16, 16),
            .tower = try SpriteSheet.load(renderer, "res/MiniWorldSprites/Buildings/Wood/Tower.png", 16, 16),
            .fireballProjectile = try SpriteSheet.load(renderer, "res/MiniWorldSprites/Objects/FireballProjectile.png", 16, 16),
        };
    }

    fn deinit(self: *@This()) void {
        self.redDemon.deinit();
        self.tower.deinit();
        self.fireballProjectile.deinit();
    }
};

const FieldObject = struct {
    pos: Vec2,
    size: Vec2,
};

const Health = struct {
    maxHealth: u32,
    health: u32,
};

const Tower = struct {
    fireDelay: u64,
    missileSpeed: f32,
    lastFire: u64 = 0,
    closestMonster: Id, // equals to itself when no monster is found.
    closestMonsterDistance: f32 = 0,
};

const Monster = struct {
    speed: f32,
};

const Projectile = struct {
    v: f32,
    target: Id,
};

const Sprite = struct {
    texture: *sdl.SDL_Texture,

    src: sdl.SDL_Rect,
};

const Animation = struct {
    sheet: *SpriteSheet,
    sprites: []const SpriteSheet.Coords,
    animationDelay: u32,
    i: usize = 0,
    lastFrame: u64 = 0,
};

const Game = struct {
    displaySize: Vec2,

    lastTicks: u32 = 0,
    ids: table.IdManager = .{},

    view: Rect = undefined,
    resources: Resources = undefined,
    objects: Table(FieldObject) = undefined,
    healths: Table(Health) = undefined,
    towers: Table(Tower) = undefined,
    monsters: Table(Monster) = undefined,
    projectiles: Table(Projectile) = undefined,
    sprites: Table(Sprite) = undefined,
    animations: Table(Animation) = undefined,

    fn init(self: *Game, allocator: std.mem.Allocator, renderer: *sdl.SDL_Renderer) !void {
        self.resources = try Resources.init(renderer);

        self.objects = try @TypeOf(self.objects).init(allocator);
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

        const grid = 200;
        const step = 20;

        var i: i32 = -grid + 1;
        while (i < grid) : (i += 1) {
            var j: i32 = -grid + 1;
            while (j < grid) : (j += 1) {
                if (i < 5 and i > -5 and j < 5 and j > -5) {
                    continue;
                }
                const id = self.ids.nextId();
                try self.monsters.add(id, .{ .speed = 10 });
                try self.healths.add(id, .{ .maxHealth = 100, .health = 100 });
                try self.objects.add(id, .{
                    .pos = .{ .x = @intToFloat(f32, i) * step, .y = @intToFloat(f32, j) * step },
                    .size = .{ .x = 8, .y = 8 },
                });
                try self.animations.add(id, .{ .animationDelay = 200, .i = id % 4, .sheet = &self.resources.redDemon, .sprites = &[_]SpriteSheet.Coords{
                    .{ .x = 2, .y = 0 },
                    .{ .x = 3, .y = 0 },
                    .{ .x = 4, .y = 0 },
                    .{ .x = 3, .y = 0 },
                } });
            }
        }

        {
            const id = self.ids.nextId();
            try self.towers.add(id, .{ .fireDelay = 500, .missileSpeed = 300, .closestMonster = id });
            try self.healths.add(id, .{ .maxHealth = 100, .health = 100 });
            // todo: no animation should be necessary for tower
            try self.objects.add(id, .{
                .pos = .{ .x = 0, .y = 0 },
                .size = .{ .x = 8, .y = 8 },
            });
            try self.sprites.add(id, self.resources.tower.sprite(0, 0));
        }
    }

    fn deinit(self: *Game) void {
        self.resources.deinit();
        self.objects.deinit();
        self.healths.deinit();
        self.monsters.deinit();
        self.towers.deinit();
        self.projectiles.deinit();
        self.sprites.deinit();
        self.animations.deinit();
    }

    fn delete(self: *Game, id: Id) !void {
        try self.objects.delete(id);
        try self.healths.delete(id);
        try self.monsters.delete(id);
        try self.towers.delete(id);
        try self.projectiles.delete(id);
        try self.sprites.delete(id);
        try self.animations.delete(id);
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
                const mo = try self.objects.get(monsterEntry.id);

                var towerIt = self.towers.iterator();
                while (towerIt.next()) |towerEntry| {
                    const to = try self.objects.get(towerEntry.id);
                    const d = to.pos.dist(mo.pos);
                    if (towerEntry.value.closestMonster == towerEntry.id or d < towerEntry.value.closestMonsterDistance) {
                        towerEntry.value.closestMonster = monsterEntry.id;
                        towerEntry.value.closestMonsterDistance = d;
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
            const o = try self.objects.get(entry.id);

            const d = Vec2.minus(c, o.pos);
            const n = d.norm();
            if (n > 1.0e-2) {
                const dn = d.mul(entry.value.speed * dt / n);
                o.pos = o.pos.add(dn);
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
            try self.sprites.add(entry.id, animation.sheet.sprite(coords.x, coords.y));
        }
    }

    fn updateTowers(self: *Game, ticks: u32) !void {
        try self.updateClosestMonsters();

        {
            // fire from towers
            var it = self.towers.iterator();
            while (it.next()) |entry| {
                const tower = &entry.value;

                if (tower.closestMonster == entry.id or
                    ticks - tower.lastFire < tower.fireDelay)
                {
                    continue;
                }

                tower.lastFire = ticks;
                const id = self.ids.nextId();
                try self.projectiles.add(id, .{ .target = tower.closestMonster, .v = tower.missileSpeed });
                // todo: no animation should not be necessary for projectile
                try self.objects.add(id, .{
                    .pos = (try self.objects.get(entry.id)).pos,
                    .size = .{ .x = 8, .y = 8 },
                });
                try self.sprites.add(id, self.resources.fireballProjectile.sprite(0, 0));
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
                const projectile = try self.objects.get(entry.id);
                const target = self.objects.find(entry.value.target) orelse {
                    // this projectile's target doesn't exist anymore, delete it.
                    try toDelete.add(entry.id, {});
                    continue;
                };

                const ds = entry.value.v * dt;

                const dir = target.value.pos.minus(projectile.pos);
                const n = dir.norm();
                if (n < ds) {
                    try toDelete.add(entry.value.target, {});
                    try toDelete.add(entry.id, {});
                } else {
                    const dn = dir.mul(ds / n);
                    projectile.pos = projectile.pos.add(dn);
                }
            }

            var toDeleteIt = toDelete.iterator();
            while (toDeleteIt.next()) |entry| {
                // std.log.debug("deleting: {}", .{entry.id});
                try self.delete(entry.id);
            }
        }
    }

    fn update(self: *Game, frameAllocator: std.mem.Allocator, ticks: u32) !void {
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
        var sdlViewport: sdl.SDL_Rect = undefined;
        sdl.SDL_RenderGetViewport(renderer, &sdlViewport);

        const viewport = Rect.sized(.{ .x = @intToFloat(f32, sdlViewport.x), .y = @intToFloat(f32, sdlViewport.y) }, .{ .x = @intToFloat(f32, sdlViewport.w), .y = @intToFloat(f32, sdlViewport.h) });
        const view = self.view;

        // std.log.info("viewport: {}", .{viewport});
        // std.log.info("view: {}", .{view});

        const translation = viewport.a.minus(view.a);
        const scale = viewport.size().x / view.size().x;
        // std.log.info("translation: {} scale: {}", .{ translation, scale });

        try checkInt(sdl.SDL_SetRenderDrawColor(renderer, 0xff, 0, 0, 0xff));

        // draw objects
        var it = self.sprites.iterator();
        while (it.next()) |entry| {
            const sprite = entry.value;
            const o = try self.objects.get(entry.id);
            const rect = Rect.centered(o.pos, o.size);
            if (self.view.intersects(rect)) {
                const pos = o.pos.add(translation).mul(scale);
                const size = o.size.mul(scale);

                const destRect = sdl.SDL_Rect{
                    .x = @floatToInt(i32, pos.x - size.x / 2),
                    .y = @floatToInt(i32, pos.y - size.y / 2),
                    .w = @floatToInt(i32, size.x),
                    .h = @floatToInt(i32, size.y),
                };

                try checkInt(sdl.SDL_RenderCopy(renderer, sprite.texture, &sprite.src, &destRect));
            }
        }
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

    const window = sdl.SDL_CreateWindow("ZTD", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, displayMode.w, displayMode.h, sdl.SDL_WINDOW_SHOWN);
    if (window == null) {
        return AppError.SdlInitError;
    }
    defer sdl.SDL_DestroyWindow(window);
    try checkInt(sdl.SDL_SetWindowFullscreen(window, sdl.SDL_WINDOW_FULLSCREEN));

    try checkInt(sdl.TTF_Init());
    defer sdl.TTF_Quit();

    const font = sdl.TTF_OpenFont("res/RubikMonoOne-Regular.ttf", 28);
    if (font == null) {
        return AppError.ResourceError;
    }
    defer sdl.TTF_CloseFont(font);

    var renderer = try checkNotNull(sdl.SDL_Renderer, sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED | sdl.SDL_RENDERER_PRESENTVSYNC));
    defer sdl.SDL_DestroyRenderer(renderer);

    var game: Game = .{
        .displaySize = .{ .x = @intToFloat(f32, displayMode.w), .y = @intToFloat(f32, displayMode.h) },
    };
    try game.init(allocator, renderer);
    defer game.deinit();

    // main loop

    const startTicks = sdl.SDL_GetTicks();
    var lastFrameTicks = startTicks;

    mainloop: while (true) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const frameAllocator = arena.allocator();

        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => break :mainloop,
                sdl.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    sdl.SDLK_ESCAPE => break :mainloop,
                    else => game.event(&event),
                },
                else => game.event(&event),
            }
        }
        const frameTicks = sdl.SDL_GetTicks();
        try game.update(frameAllocator, frameTicks);

        try checkInt(sdl.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff));
        try checkInt(sdl.SDL_RenderClear(renderer));

        try game.render(renderer);

        // draw fps
        if (frameTicks > lastFrameTicks) {
            var text = try std.fmt.allocPrintZ(frameAllocator, "FPS: {}", .{1000 / (frameTicks - lastFrameTicks)});
            const tt: [*:0]const u8 = text;
            const textSurface = sdl.TTF_RenderText_Solid(font, tt, .{ .r = 0, .g = 0, .b = 255, .a = 255 });
            defer sdl.SDL_FreeSurface(textSurface);

            const texture = try checkNotNull(sdl.SDL_Texture, sdl.SDL_CreateTextureFromSurface(renderer, textSurface));
            defer sdl.SDL_DestroyTexture(texture);

            const srcRect: sdl.SDL_Rect = .{
                .x = 0,
                .y = 0,
                .w = textSurface.*.w,
                .h = textSurface.*.h,
            };
            const dstRect: sdl.SDL_Rect = .{
                .x = 0,
                .y = 0,
                .w = textSurface.*.w,
                .h = textSurface.*.h,
            };

            try checkInt(sdl.SDL_RenderCopy(renderer, texture, &srcRect, &dstRect));
        }

        sdl.SDL_RenderPresent(renderer);

        lastFrameTicks = frameTicks;
    }
}
