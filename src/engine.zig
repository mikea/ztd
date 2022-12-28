const std = @import("std");
const table = @import("table.zig");
const sprites = @import("sprites.zig");
const model = @import("model.zig");
const Id = model.Id;
const maxId = model.maxId;

const gl = @import("gl.zig");

const geom = @import("geom.zig");
const Vec = geom.Vec;
const Rect = geom.Rect;

const SparseSet = @import("sparse_set.zig").SparseSet;
const Viewport = @import("viewport.zig").Viewport;

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

pub const Engine = struct {
    const BoundsTable = table.RTable(Id, maxId);
    const SpritesTable = table.Table(Id, maxId, model.Sprite);
    const AnimationsTable = table.Table(Id, maxId, model.Animation);

    window: *gl.c.GLFWwindow,

    viewport: Viewport,
    spriteRenderer: sprites.SpriteRenderer,

    // tables
    // will be deleted at the end of the update
    toDelete: SparseSet(Id, maxId, void),
    bounds: BoundsTable,
    sprites: SpritesTable,
    animations: AnimationsTable,
    healths: model.HealthsTable,
    particles: model.ParticlesTable,

    ids: IdManager,
    running: bool = true,
    mousePos: Vec = .{ .x = 0, .y = 0 },
    renderedSprites: usize = 0,

    pub fn init(allocator: std.mem.Allocator, window: *gl.c.GLFWwindow) !Engine {
        return .{
            .window = window,
            .ids = try IdManager.init(allocator),
            .viewport = Viewport.init(window),
            .spriteRenderer = try sprites.SpriteRenderer.init(),
            .toDelete = try SparseSet(Id, maxId, void).init(allocator),
            .bounds = try BoundsTable.init(allocator),
            .sprites = try SpritesTable.init(allocator),
            .animations = try AnimationsTable.init(allocator),
            .healths = try model.HealthsTable.init(allocator),
            .particles = try model.ParticlesTable.init(allocator),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.bounds.deinit();
        self.sprites.deinit();
        self.animations.deinit();
        self.healths.deinit();
        self.particles.deinit();
        self.toDelete.deinit();
        self.ids.deinit();
        self.spriteRenderer.deinit();
    }

    pub fn delete(self: *Engine, id: Id) !void {
        self.bounds.delete(id);
        self.sprites.delete(id);
        self.animations.delete(id);
        self.healths.delete(id);
        self.particles.delete(id);
        try self.ids.free(id);
    }

    // pub fn nextEvent(self: *Engine) ?sdl.c.SDL_Event {
    //     var event: sdl.c.SDL_Event = undefined;
    //     while (sdl.c.SDL_PollEvent(&event) != 0) {
    //         switch (event.type) {
    //             sdl.c.SDL_QUIT => self.running = false,
    //             sdl.c.SDL_KEYDOWN => switch (event.key.keysym.sym) {
    //                 sdl.c.SDLK_q => self.running = false,
    //                 else => {},
    //             },
    //             sdl.c.SDL_MOUSEMOTION => {
    //                 const screenPos = Vec{ .x = @intToFloat(f32, event.motion.x), .y = @intToFloat(f32, event.motion.y) };
    //                 self.mousePos = self.viewport.screenToGame(screenPos);
    //             },
    //             else => {},
    //         }

    //         self.viewport.onEvent(&event);

    //         return event;
    //     }

    //     return null;
    // }

    pub fn onEvent(self: *Engine, event: *const gl.Event) void {
        self.viewport.onEvent(event);
    }

    pub fn updateAnimations(self: *Engine, ticks: u64) !void {
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

    pub fn updateParticles(self: *Engine, ticks: u64, dt: f32) !void {
        var it = self.particles.iterator();
        while (it.next()) |entry| {
            const particle = entry.value;
            if (ticks >= particle.endTicks) {
                try self.toDelete.set(entry.id, {});
                switch (particle.onComplete) {
                    .DO_NOTHING => {},
                    .FREE_TEXTURE => {
                        // const sprite = self.sprites.get(entry.id);
                        // sdl.c.SDL_DestroyTexture(sprite.texture);
                        @panic("not implemented");
                    },
                }
                continue;
            }
            const bound = self.bounds.get(entry.id);
            try self.bounds.update(entry.id, bound.translate(particle.v.scale(dt)));
        }
    }

    pub fn render(self: *Engine) !void {
        gl.c.glClearColor(1.0, 1.0, 1.0, 1.0);
        gl.c.glClear(gl.c.GL_COLOR_BUFFER_BIT);

        self.viewport.update();
        try self.renderSprites();
    }

    fn renderSprites(self: *Engine) !void {
        self.renderedSprites = 0;
        self.spriteRenderer.startFrame(&self.viewport);
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
                        // const destRect = s.engine.viewport.toScreen(rect);
                        s.engine.spriteRenderer.renderSprite(sprite, &rect);
                        // checkInt(sdl.c.SDL_RenderCopyEx(s.engine.renderer, sprite.texture, &sprite.src, &destRect, 360 * sprite.angleRad / (2 * std.math.pi), null, sdl.c.SDL_FLIP_NONE));

                        if (s.engine.healths.find(id)) |health| {
                            if (health.*.health < health.*.maxHealth) {
                                // display health underneath the main sprite
                                const healthRatio = std.math.max(health.*.health, 0) / health.*.maxHealth;
                                const healthRect = Rect{
                                    .a = .{ .x = rect.a.x, .y = rect.b.y },
                                    .b = .{ .x = rect.a.x + (rect.b.x - rect.a.x) * healthRatio, .y = rect.b.y + 1 },
                                };
                                // const destHealthRect = s.engine.viewport.toScreen(healthRect);
                                // checkInt(sdl.c.SDL_SetRenderDrawColor(s.engine.renderer, 0, 255, 0, 255));
                                // checkInt(sdl.c.SDL_RenderFillRect(s.engine.renderer, &destHealthRect));
                                _ = healthRect;
                            }
                        }
                    }
                }
            } = .{ .engine = self, .z = layer };

            try self.bounds.findIntersect(self.viewport.view, @TypeOf(renderer), &renderer, @TypeOf(renderer).callback);
        }
    }

    // fn renderText(self: *Engine) !void {
    //     var it = self.texts.iterator();
    //     while (it.next()) |entry| {
    //         var text = entry.value;

    //         if (text.texture == null) {
    //             text.texture = checkNotNull(sdl.c.SDL_Texture, sdl.c.SDL_CreateTextureFromSurface(self.renderer, text.surface));
    //         }

    //         const srcRect: sdl.c.SDL_Rect = .{
    //             .x = 0,
    //             .y = 0,
    //             .w = text.surface.*.w,
    //             .h = text.surface.*.h,
    //         };
    //         const dstRect: sdl.c.SDL_Rect = .{
    //             .x = @floatToInt(i32, text.pos.x),
    //             .y = @floatToInt(i32, text.pos.y),
    //             .w = text.surface.*.w,
    //             .h = text.surface.*.h,
    //         };

    //         checkInt(sdl.c.SDL_RenderCopy(self.renderer, text.texture, &srcRect, &dstRect));
    //     }
    // }

    // pub fn setText(self: *Engine, id: Id, text: [:0]const u8, pos: Vec, alignment: Alignment, color: sdl.c.SDL_Color, font: *sdl.c.TTF_Font) !void {
    //     if (self.texts.find(id)) |t| {
    //         t.destroy();
    //     }

    //     const surface = sdl.c.TTF_RenderText_Solid_Wrapped(font, @as([*:0]const u8, text), color, 0);
    //     const w = @intToFloat(f32, surface.*.w);
    //     const alignedPos = switch (alignment) {
    //         Alignment.LEFT => pos,
    //         Alignment.CENTER => pos.minus(.{ .x = w / 2, .y = 0 }),
    //         Alignment.RIGHT => pos.minus(.{ .x = w, .y = 0 }),
    //     };
    //     try self.texts.set(id, .{ .surface = surface, .pos = alignedPos, .alignment = alignment, .texture = null });
    // }
};
