const std = @import("std");
const table = @import("table.zig");
const geom = @import("geom.zig");

const sdlZig = @import("sdl.zig");
const sdl = sdlZig.sdl;
const checkNotNull = sdlZig.checkNotNull;
const checkInt = sdlZig.checkInt;
const Sprite = sdlZig.Sprite;

const Vec = geom.Vec2;
const Rect = geom.Rect;

pub const Id = u32;
pub const maxId: usize = 1 << 18;

pub const IdManager = struct {
    i: Id = 0,

    pub fn nextId(self: *@This()) Id {
        if (self.i == maxId) {
            std.log.err("too many ids allocated: max={}", .{maxId});
            @panic("too many ids");
        }
        const result = self.i;
        self.i += 1;
        return result;
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
    surface: *sdl.SDL_Surface,
    texture: ?*sdl.SDL_Texture,

    // todo: call on table cleanup
    fn destroy(self: *Text) void {
        sdl.SDL_DestroyTexture(self.texture);
        sdl.SDL_FreeSurface(self.surface);
    }
};

const Animation = struct {
    sheet: *sdlZig.SpriteSheet,
    sprites: []const sdlZig.SpriteSheet.Coords,
    animationDelay: u32,
    i: usize = 0,
    lastFrame: u64 = 0,
};

const Viewport = struct {
    displaySize: Vec,
    view: Rect = undefined,

    pub fn screenToGame(self: *const Viewport, screenPos: Vec) Vec {
        const norm = screenPos.ratio(self.displaySize);
        return self.view.a.add(self.view.size().mul(norm));
    }
};

pub const Engine = struct {
    const BoundsTable = table.RTable(Id, maxId);
    const TextsTable = table.Table(Id, maxId, Text);
    const SpritesTable = table.Table(Id, maxId, Sprite);
    const AnimationsTable = table.Table(Id, maxId, Animation);

    viewport: Viewport,
    renderer: *sdl.SDL_Renderer,

    // tables
    bounds: BoundsTable,
    texts: TextsTable,
    sprites: SpritesTable,
    animations: AnimationsTable,

    ids: IdManager = .{},
    running: bool = true,
    mousePos: Vec = .{ .x = 0, .y = 0 },

    pub fn init(allocator: std.mem.Allocator, renderer: *sdl.SDL_Renderer) !Engine {
        var displayMode: sdl.SDL_DisplayMode = undefined;
        try checkInt(sdl.SDL_GetCurrentDisplayMode(0, &displayMode));

        try checkInt(sdl.SDL_SetRenderDrawBlendMode(renderer, sdl.SDL_BLENDMODE_BLEND));

        const displaySize = Vec{ .x = @intToFloat(f32, displayMode.w), .y = @intToFloat(f32, displayMode.h) };
        // initially 1000 wide, centered on origin
        const w = 1000;
        const h = w * displaySize.y / displaySize.x;
        const view = Rect{ .a = .{ .x = -w / 2, .y = -h / 2 }, .b = .{ .x = w / 2, .y = h / 2 } };

        return .{
            .renderer = renderer,
            .bounds = try BoundsTable.init(allocator),
            .texts = try TextsTable.init(allocator),
            .sprites = try SpritesTable.init(allocator),
            .animations = try AnimationsTable.init(allocator),
            .viewport = .{
                .displaySize = displaySize,
                .view = view,
            },
        };
    }

    pub fn deinit(self: *Engine) void {
        self.bounds.deinit();
        self.texts.deinit();
        self.sprites.deinit();
        self.animations.deinit();
    }

    pub fn nextEvent(self: *Engine) ?sdl.SDL_Event {
        const delta = self.viewport.view.height() / 10.0;
        const mouseZoom = 1.1;
        const kbdZoom = 1.7;

        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => self.running = false,
                sdl.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    sdl.SDLK_q => self.running = false,
                    sdl.SDLK_UP => {
                        self.viewport.view = self.viewport.view.translate(.{ .x = 0, .y = -delta });
                        return null;
                    },
                    sdl.SDLK_DOWN => {
                        self.viewport.view = self.viewport.view.translate(.{ .x = 0, .y = delta });
                        return null;
                    },
                    sdl.SDLK_LEFT => {
                        self.viewport.view = self.viewport.view.translate(.{ .x = -delta, .y = 0 });
                        return null;
                    },
                    sdl.SDLK_RIGHT => {
                        self.viewport.view = self.viewport.view.translate(.{ .x = delta, .y = 0 });
                        return null;
                    },
                    sdl.SDLK_PAGEUP => {
                        self.viewport.view = Rect.centered(self.viewport.view.center(), self.viewport.view.size().scale(kbdZoom));
                        return null;
                    },
                    sdl.SDLK_PAGEDOWN => {
                        self.viewport.view = Rect.centered(self.viewport.view.center(), self.viewport.view.size().scale(1.0 / kbdZoom));
                        return null;
                    },
                    else => {},
                },
                sdl.SDL_MOUSEWHEEL => {
                    const z: f32 = if (event.wheel.y > 0) mouseZoom else 1.0 / mouseZoom;
                    self.viewport.view = Rect.centered(self.viewport.view.center(), self.viewport.view.size().scale(z));
                    return null;
                },
                sdl.SDL_MOUSEMOTION => {
                    const screenPos = Vec{ .x = @intToFloat(f32, event.motion.x), .y = @intToFloat(f32, event.motion.y) };
                    self.mousePos = self.viewport.screenToGame(screenPos);
                },
                else => {},
            }

            return event;
        }

        return null;
    }

    pub fn update(self: *Engine, _: std.mem.Allocator, ticks: u32) !void {
        try self.updateAnimations(ticks);
    }

    fn updateAnimations(self: *Engine, ticks: u32) !void {
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

    pub fn render(self: *Engine) !void {
        try self.renderSprites();
        try self.renderText();
    }

    fn renderSprites(self: *Engine) !void {
        try checkInt(sdl.SDL_SetRenderDrawColor(self.renderer, 0xff, 0xff, 0xff, 0xff));
        try checkInt(sdl.SDL_RenderClear(self.renderer));

        var sdlViewport: sdl.SDL_Rect = undefined;
        sdl.SDL_RenderGetViewport(self.renderer, &sdlViewport);

        const viewport = Rect.initSized(.{ .x = @intToFloat(f32, sdlViewport.x), .y = @intToFloat(f32, sdlViewport.y) }, .{ .x = @intToFloat(f32, sdlViewport.w), .y = @intToFloat(f32, sdlViewport.h) });
        const view = self.viewport.view;

        const translation = viewport.a.minus(view.a);
        const scale = viewport.size().x / view.size().x;

        // draw sprites
        var it = self.sprites.iterator();
        while (it.next()) |entry| {
            const sprite = entry.value;
            const o = try self.bounds.get(entry.id);
            if (view.intersects(o)) {
                const a = o.a.add(translation).scale(scale);
                const size = o.size().scale(scale);

                const destRect = sdl.SDL_Rect{
                    .x = @floatToInt(i32, a.x),
                    .y = @floatToInt(i32, a.y),
                    .w = @floatToInt(i32, size.x),
                    .h = @floatToInt(i32, size.y),
                };

                try checkInt(sdl.SDL_RenderCopyEx(self.renderer, sprite.texture, &sprite.src, &destRect, sprite.angle, null, sdl.SDL_FLIP_NONE));
            }
        }
    }

    fn renderText(self: *Engine) !void {
        var it = self.texts.iterator();
        while (it.next()) |*entry| {
            var text = &entry.*.value;

            if (text.texture == null) {
                text.texture = try checkNotNull(sdl.SDL_Texture, sdl.SDL_CreateTextureFromSurface(self.renderer, text.surface));
            }

            const srcRect: sdl.SDL_Rect = .{
                .x = 0,
                .y = 0,
                .w = text.surface.*.w,
                .h = text.surface.*.h,
            };
            const dstRect: sdl.SDL_Rect = .{
                .x = @floatToInt(i32, text.pos.x),
                .y = @floatToInt(i32, text.pos.y),
                .w = text.surface.*.w,
                .h = text.surface.*.h,
            };

            try checkInt(sdl.SDL_RenderCopy(self.renderer, text.texture, &srcRect, &dstRect));
        }
    }

    pub fn setText(self: *Engine, id: Id, text: [:0]const u8, pos: Vec, alignment: Alignment, color: sdl.SDL_Color, font: *sdl.TTF_Font) !void {
        if (self.texts.find(id)) |entry| {
            entry.value.destroy();
        }

        const surface = sdl.TTF_RenderText_Solid(font, @as([*:0]const u8, text), color);
        const w = @intToFloat(f32, surface.*.w);
        const alignedPos = switch (alignment) {
            Alignment.LEFT => pos,
            Alignment.CENTER => pos.minus(.{ .x = w / 2, .y = 0 }),
            Alignment.RIGHT => pos.minus(.{ .x = w, .y = 0 }),
        };
        try self.texts.add(id, .{ .surface = surface, .pos = alignedPos, .alignment = alignment, .texture = null });
    }
};
