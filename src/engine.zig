const std = @import("std");
const table = @import("table.zig");
const geom = @import("geom.zig");


const sdlZig = @import("sdl.zig");
const sdl = sdlZig.sdl;
const checkNotNull = sdlZig.checkNotNull;
const checkInt = sdlZig.checkInt;


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

pub const Text = struct {
    pos: Vec,
    surface: *sdl.SDL_Surface,
    texture: ?*sdl.SDL_Texture,

    // todo: call on table cleanup
    fn destroy(self: *Text) void {
        sdl.SDL_DestroyTexture(self.texture);
        sdl.SDL_FreeSurface(self.surface);
    }
};

pub const Engine = struct {
    const BoundsTable = table.RTable(Id, maxId);
    const TextsTable = table.Table(Id, maxId, Text);

    renderer: *sdl.SDL_Renderer,
    bounds: BoundsTable,
    texts: TextsTable,

    ids: IdManager = .{},
    running: bool = true,

    pub fn init(allocator: std.mem.Allocator, renderer: *sdl.SDL_Renderer) !Engine {
        try checkInt(sdl.SDL_SetRenderDrawBlendMode(renderer, sdl.SDL_BLENDMODE_BLEND));

        return .{
            .renderer = renderer,
            .bounds = try BoundsTable.init(allocator),
            .texts = try TextsTable.init(allocator),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.bounds.deinit();
        self.texts.deinit();
    }

    pub fn nextEvent(self: *Engine) ?sdl.SDL_Event {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => self.running = false,
                sdl.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    sdl.SDLK_ESCAPE => self.running = false,
                    else => {},
                },
                else => {},
            }

            return event;
        }

        return null;
    }

    pub fn render(self: *Engine) !void {
        try self.renderText();
    }

    fn renderText(self: *Engine) !void {
        var it = self.texts.iterator();
        while (it.next()) |*entry| {
            var text = &entry.*.value;

            if (text.texture == null) {
                text.texture = try checkNotNull(sdl.SDL_Texture, sdl.SDL_CreateTextureFromSurface(self.renderer, text.surface));
            }

            const srcRect: sdl.SDL_Rect = .{ .x = 0, .y = 0, .w = text.surface.*.w, .h = text.surface.*.h, };
            const dstRect: sdl.SDL_Rect = .{ .x = @floatToInt(i32, text.pos.x), .y = @floatToInt(i32, text.pos.y), .w = text.surface.*.w, .h = text.surface.*.h, };

            try checkInt(sdl.SDL_RenderCopy(self.renderer, text.texture, &srcRect, &dstRect));
        }
    }

    pub fn setText(self: *Engine, id: Id, text: [:0]const u8, pos: Vec, color: sdl.SDL_Color, font: *sdl.TTF_Font) !void {
        if (self.texts.find(id)) |entry| {
            entry.value.destroy();
        }

        const surface = sdl.TTF_RenderText_Solid(font, @as([*:0]const u8, text), color);
        try self.texts.add(id, .{.surface = surface, .pos = pos, .texture = null});
    }
};