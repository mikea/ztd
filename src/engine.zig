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
    ids: IdManager = .{},
    bounds: table.Table(Id, maxId, Rect) = undefined,
    texts: table.Table(Id, maxId, Text) = undefined,

    pub fn init(self: *Engine, allocator: std.mem.Allocator, _: *sdl.SDL_Renderer) !void {
        self.bounds = try @TypeOf(self.bounds).init(allocator);
        self.texts = try @TypeOf(self.texts).init(allocator);
    }

    pub fn deinit(self: *Engine) void {
        self.bounds.deinit();
        self.texts.deinit();
    }

    pub fn render(self: *Engine, renderer: *sdl.SDL_Renderer) !void {
        try self.renderText(renderer);
    }

    fn renderText(self: *Engine, renderer: *sdl.SDL_Renderer) !void {
        var it = self.texts.iterator();
        while (it.next()) |*entry| {
            var text = &entry.*.value;

            if (text.texture == null) {
                text.texture = try checkNotNull(sdl.SDL_Texture, sdl.SDL_CreateTextureFromSurface(renderer, text.surface));
            }

            const srcRect: sdl.SDL_Rect = .{ .x = 0, .y = 0, .w = text.surface.*.w, .h = text.surface.*.h, };
            const dstRect: sdl.SDL_Rect = .{ .x = @floatToInt(i32, text.pos.x), .y = @floatToInt(i32, text.pos.y), .w = text.surface.*.w, .h = text.surface.*.h, };

            try checkInt(sdl.SDL_RenderCopy(renderer, text.texture, &srcRect, &dstRect));
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