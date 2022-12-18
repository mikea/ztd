const std = @import("std");
const table = @import("table.zig");

const model = @import("model.zig");
const Id = model.Id;
const maxId = model.maxId;

const sdl = @import("sdl.zig");
const checkNotNull = sdl.checkNotNull;
const checkInt = sdl.checkInt;

const geom = @import("geom.zig");
const Vec = geom.Vec;
const Rect = geom.Rect;

const SparseSet = @import("sparse_set.zig").SparseSet;

pub const IdManager = struct {
    i: Id = 0,
    avail: SparseSet(Id, maxId, void),

    pub fn init(allocator: std.mem.Allocator) !IdManager {
        return .{ .avail = try SparseSet(Id, maxId, void).init(allocator) };
    }

    pub fn deinit(self: *@This()) void {
        self.avail.deinit();
    }

    pub fn nextId(self: *@This()) Id {
        if (self.i == maxId) {
            if (self.avail.size() == 0) {
                @panic("too many ids");
            }
            return self.avail.pop();
        }
        // no id 0!
        self.i += 1;
        return self.i;
    }

    pub fn free(self: *@This(), id: Id) !void {
        try self.avail.set(id, {});
    }
};

pub const Alignment = enum {
    LEFT,
    CENTER,
    RIGHT,
};

pub const Text = struct {
    pos: Vec,
    alignment: Alignment,
    surface: *sdl.c.SDL_Surface,
    texture: ?*sdl.c.SDL_Texture,

    // todo: call on table cleanup
    fn destroy(self: *Text) void {
        sdl.c.SDL_DestroyTexture(self.texture);
        sdl.c.SDL_FreeSurface(self.surface);
    }
};

pub const Engine = struct {
    const BoundsTable = table.RTable(Id, maxId);
    const TextsTable = table.Table(Id, maxId, Text);
    const SpritesTable = table.Table(Id, maxId, model.Sprite);
    const AnimationsTable = table.Table(Id, maxId, model.Animation);

    viewport: Viewport,
    renderer: *sdl.Renderer,

    // tables
    // will be deleted at the end of the update
    toDelete: SparseSet(Id, maxId, void),
    bounds: BoundsTable,
    texts: TextsTable,
    sprites: SpritesTable,
    animations: AnimationsTable,
    healths: model.HealthsTable,
    particles: model.ParticlesTable,

    ids: IdManager,
    running: bool = true,
    mousePos: Vec = .{ .x = 0, .y = 0 },
    renderedSprites: usize = 0,

    pub fn init(allocator: std.mem.Allocator, renderer: *sdl.Renderer) !Engine {
        var displayMode: sdl.c.SDL_DisplayMode = undefined;
        checkInt(sdl.c.SDL_GetCurrentDisplayMode(0, &displayMode));

        checkInt(sdl.c.SDL_SetRenderDrawBlendMode(renderer, sdl.c.SDL_BLENDMODE_BLEND));

        const displaySize = Vec{ .x = @intToFloat(f32, displayMode.w), .y = @intToFloat(f32, displayMode.h) };

        return .{
            .ids = try IdManager.init(allocator),
            .renderer = renderer,
            .viewport = Viewport.init(displaySize),
            .toDelete = try SparseSet(Id, maxId, void).init(allocator),
            .bounds = try BoundsTable.init(allocator),
            .texts = try TextsTable.init(allocator),
            .sprites = try SpritesTable.init(allocator),
            .animations = try AnimationsTable.init(allocator),
            .healths = try model.HealthsTable.init(allocator),
            .particles = try model.ParticlesTable.init(allocator),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.bounds.deinit();
        self.texts.deinit();
        self.sprites.deinit();
        self.animations.deinit();
        self.healths.deinit();
        self.particles.deinit();
        self.toDelete.deinit();
        self.ids.deinit();
    }

    pub fn delete(self: *Engine, id: Id) !void {
        try self.bounds.delete(id);
        try self.texts.delete(id);
        try self.sprites.delete(id);
        try self.animations.delete(id);
        try self.healths.delete(id);
        try self.particles.delete(id);
        try self.ids.free(id);
    }

    pub fn nextEvent(self: *Engine) ?sdl.c.SDL_Event {
        var event: sdl.c.SDL_Event = undefined;
        while (sdl.c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.c.SDL_QUIT => self.running = false,
                sdl.c.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    sdl.c.SDLK_q => self.running = false,
                    else => {},
                },
                sdl.c.SDL_MOUSEMOTION => {
                    const screenPos = Vec{ .x = @intToFloat(f32, event.motion.x), .y = @intToFloat(f32, event.motion.y) };
                    self.mousePos = self.viewport.screenToGame(screenPos);
                },
                else => {},
            }

            self.viewport.onEvent(&event);

            return event;
        }

        return null;
    }

    pub fn updateAnimations(self: *Engine, ticks: usize) !void {
        if (self.viewport.view.height() > 5000) {
            // do not update animation when zoomed out too much
            return;
        }

        var updater: struct {
            engine: *Engine,
            ticks: usize,
            pub fn callback(s: *@This(), id: Id, _: Rect) error{OutOfMemory}!void {
                if (s.engine.animations.find(id)) |animation| {
                    const i = (s.ticks / animation.animationDelay + animation.i) % animation.coords.len;
                    const coords = animation.coords[i];
                    try s.engine.sprites.set(id, animation.sheet.sprite(coords.x, coords.y, 0, animation.z));
                }
            }
        } = .{ .engine = self, .ticks = ticks };

        try self.bounds.findIntersect(self.viewport.view, @TypeOf(updater), &updater, @TypeOf(updater).callback);
    }

    pub fn updateParticles(self: *Engine, ticks: usize, dt: f32) !void {
        var it = self.particles.iterator();
        while (it.next()) |entry| {
            const particle = entry.value;
            if (ticks >= particle.endTicks) {
                try self.toDelete.set(entry.id, {});
                switch (particle.onComplete) {
                    .DO_NOTHING => {},
                    .FREE_TEXTURE => {
                        const sprite = self.sprites.get(entry.id);
                        sdl.c.SDL_DestroyTexture(sprite.texture);
                    },
                }
                continue;
            }
            const bound = self.bounds.get(entry.id);
            try self.bounds.update(entry.id, bound.translate(particle.v.scale(dt)));
        }
    }

    pub fn render(self: *Engine) !void {
        try self.renderSprites();
        try self.renderText();
    }

    fn renderSprites(self: *Engine) !void {
        checkInt(sdl.c.SDL_SetRenderDrawColor(self.renderer, 0xff, 0xff, 0xff, 0xff));
        checkInt(sdl.c.SDL_RenderClear(self.renderer));

        self.renderedSprites = 0;
        for (std.enums.values(model.Layer)) |layer| {
            var renderer: struct {
                engine: *Engine,
                z: model.Layer,

                pub fn callback(s: *@This(), id: Id, rect: Rect) error{OutOfMemory}!void {
                    if (s.engine.sprites.find(id)) |sprite| {
                        if (s.z != sprite.z) {
                            return;
                        }
                        s.engine.renderedSprites += 1;
                        const destRect = s.engine.viewport.toScreen(rect);
                        checkInt(sdl.c.SDL_RenderCopyEx(s.engine.renderer, sprite.texture, &sprite.src, &destRect, 360 * sprite.angleRad / (2 * std.math.pi), null, sdl.c.SDL_FLIP_NONE));

                        if (s.engine.healths.find(id)) |health| {
                            if (health.*.health < health.*.maxHealth) {
                                // display health underneath the main sprite
                                const healthRatio = std.math.max(health.*.health, 0) / health.*.maxHealth;
                                const healthRect = Rect{
                                    .a = .{ .x = rect.a.x, .y = rect.b.y },
                                    .b = .{ .x = rect.a.x + (rect.b.x - rect.a.x) * healthRatio, .y = rect.b.y + 1 },
                                };
                                const destHealthRect = s.engine.viewport.toScreen(healthRect);
                                checkInt(sdl.c.SDL_SetRenderDrawColor(s.engine.renderer, 0, 255, 0, 255));
                                checkInt(sdl.c.SDL_RenderFillRect(s.engine.renderer, &destHealthRect));
                            }
                        }
                    }
                }
            } = .{ .engine = self, .z = layer };

            try self.bounds.findIntersect(self.viewport.view, @TypeOf(renderer), &renderer, @TypeOf(renderer).callback);
        }
    }

    fn renderText(self: *Engine) !void {
        var it = self.texts.iterator();
        while (it.next()) |entry| {
            var text = entry.value;

            if (text.texture == null) {
                text.texture = checkNotNull(sdl.c.SDL_Texture, sdl.c.SDL_CreateTextureFromSurface(self.renderer, text.surface));
            }

            const srcRect: sdl.c.SDL_Rect = .{
                .x = 0,
                .y = 0,
                .w = text.surface.*.w,
                .h = text.surface.*.h,
            };
            const dstRect: sdl.c.SDL_Rect = .{
                .x = @floatToInt(i32, text.pos.x),
                .y = @floatToInt(i32, text.pos.y),
                .w = text.surface.*.w,
                .h = text.surface.*.h,
            };

            checkInt(sdl.c.SDL_RenderCopy(self.renderer, text.texture, &srcRect, &dstRect));
        }
    }

    pub fn setText(self: *Engine, id: Id, text: [:0]const u8, pos: Vec, alignment: Alignment, color: sdl.c.SDL_Color, font: *sdl.c.TTF_Font) !void {
        if (self.texts.find(id)) |t| {
            t.destroy();
        }

        const surface = sdl.c.TTF_RenderText_Solid_Wrapped(font, @as([*:0]const u8, text), color, 0);
        const w = @intToFloat(f32, surface.*.w);
        const alignedPos = switch (alignment) {
            Alignment.LEFT => pos,
            Alignment.CENTER => pos.minus(.{ .x = w / 2, .y = 0 }),
            Alignment.RIGHT => pos.minus(.{ .x = w, .y = 0 }),
        };
        try self.texts.set(id, .{ .surface = surface, .pos = alignedPos, .alignment = alignment, .texture = null });
    }
};

const Viewport = struct {
    displaySize: Vec,
    screen: Rect,
    view: Rect,

    // lower left corner translation, computed from view and screen on every view update
    translation: Vec,
    // computed from view and screen on every view update
    scale: f32,

    pub fn init(displaySize: Vec) Viewport {
        // initially 1000 wide, centered on origin
        const w = 1000;
        const h = w * displaySize.y / displaySize.x;
        const view = Rect{ .a = .{ .x = -w / 2, .y = -h / 2 }, .b = .{ .x = w / 2, .y = h / 2 } };
        const screen = Rect.initSized(.{ .x = 0, .y = 0 }, displaySize);

        return .{ .displaySize = displaySize, .screen = screen, .view = view, .translation = screen.a.minus(view.a), .scale = screen.size().x / view.size().x };
    }

    pub fn screenToGame(self: *const Viewport, screenPos: Vec) Vec {
        const norm = screenPos.ratio(self.displaySize);
        return self.view.a.add(self.view.size().mul(norm));
    }

    pub fn toScreen(self: *const Viewport, rect: Rect) sdl.c.SDL_Rect {
        const a = Vec{
            .x = (rect.a.x + self.translation.x) * self.scale,
            .y = (rect.a.y + self.translation.y) * self.scale,
        };
        const size = rect.size().scale(self.scale);

        return .{
            .x = @floatToInt(i32, a.x),
            .y = @floatToInt(i32, a.y),
            .w = @floatToInt(i32, size.x),
            .h = @floatToInt(i32, size.y),
        };
    }

    pub fn onEvent(self: *Viewport, event: *sdl.c.SDL_Event) void {
        const delta = self.view.height() / 10.0;
        const mouseZoom = 1.1;
        const kbdZoom = 1.7;

        switch (event.type) {
            sdl.c.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                sdl.c.SDLK_UP => {
                    self.view = self.view.translate(.{ .x = 0, .y = -delta });
                },
                sdl.c.SDLK_DOWN => {
                    self.view = self.view.translate(.{ .x = 0, .y = delta });
                },
                sdl.c.SDLK_LEFT => {
                    self.view = self.view.translate(.{ .x = -delta, .y = 0 });
                },
                sdl.c.SDLK_RIGHT => {
                    self.view = self.view.translate(.{ .x = delta, .y = 0 });
                },
                sdl.c.SDLK_PAGEUP => {
                    self.view = Rect.centered(self.view.center(), self.view.size().scale(kbdZoom));
                },
                sdl.c.SDLK_PAGEDOWN => {
                    self.view = Rect.centered(self.view.center(), self.view.size().scale(1.0 / kbdZoom));
                },
                else => {},
            },
            sdl.c.SDL_MOUSEWHEEL => {
                const z: f32 = if (event.wheel.y > 0) mouseZoom else 1.0 / mouseZoom;
                self.view = Rect.centered(self.view.center(), self.view.size().scale(z));
                std.log.debug("height: {}", .{self.view.height()});
            },
            else => {},
        }

        self.translation = self.screen.a.minus(self.view.a);
        self.scale = self.screen.size().x / self.view.size().x;
    }
};
