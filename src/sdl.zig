const std = @import("std");

pub const sdl = @cImport({
    @cInclude("SDL.h");
    @cInclude("SDL_image.h");
    @cInclude("SDL_ttf.h");
});

const cairo = @cImport({
    @cInclude("cairo.h");
});

pub const Renderer = sdl.SDL_Renderer;
pub const Event = sdl.SDL_Event;

const SdlError = error{
    SdlError,
};

pub fn checkInt(i: c_int) !void {
    if (i < 0) {
        return SdlError.SdlError;
    }
}

pub fn checkNotNull(comptime T: type, ptr: ?*T) !*T {
    return ptr orelse SdlError.SdlError;
}

pub const Sprite = struct {
    texture: *sdl.SDL_Texture,
    src: sdl.SDL_Rect,
    angle: f64,
};

pub const SpriteSheet = struct {
    texture: *sdl.SDL_Texture,
    w: u16,
    h: u16,

    pub fn load(renderer: *sdl.SDL_Renderer, file: [*:0]const u8, w: u16, h: u16) !SpriteSheet {
        const texture = try checkNotNull(sdl.SDL_Texture, sdl.IMG_LoadTexture(renderer, file));
        return .{ .texture = texture, .w = w, .h = h };
    }

    pub fn deinit(self: *@This()) void {
        sdl.SDL_DestroyTexture(self.texture);
    }

    pub const Coords = struct {
        x: u16,
        y: u16,
    };

    pub fn sprite(self: *@This(), x: u16, y: u16, angle: f64) Sprite {
        return .{ .texture = self.texture, .src = sdl.SDL_Rect{
            .x = x * self.w,
            .y = y * self.h,
            .w = self.w,
            .h = self.h,
        }, .angle = angle };
    }
};

pub fn drawCircle(renderer: *sdl.SDL_Renderer, r: f32) !Sprite {
    const w = r * 2 + 1;
    const wint = @floatToInt(i32, w);
    const texture = try checkNotNull(sdl.SDL_Texture, sdl.SDL_CreateTexture(renderer, sdl.SDL_PIXELFORMAT_ARGB8888, sdl.SDL_TEXTUREACCESS_STREAMING, wint, wint));
    var pitch: c_int = undefined;
    var pixels: [*c]u8 = undefined;
    try checkInt(sdl.SDL_LockTexture(texture, null, @ptrCast([*c]?*anyopaque, &pixels), &pitch));

    const cairoSurface = cairo.cairo_image_surface_create_for_data(pixels, cairo.CAIRO_FORMAT_ARGB32, wint, wint, pitch);
    const cr = cairo.cairo_create(cairoSurface);

    cairo.cairo_set_source_rgba(cr, 1, 1, 1, 0);
    cairo.cairo_rectangle(cr, 0, 0, w, w);
    cairo.cairo_fill(cr);

    cairo.cairo_set_source_rgba(cr, 1.0, 0, 0, 1);
    cairo.cairo_arc(cr, w/2, w/2, r, 0, 2 * std.math.pi);
    cairo.cairo_set_line_width(cr, 0.5);
    cairo.cairo_stroke(cr);

    sdl.SDL_UnlockTexture(texture);

    try checkInt(sdl.SDL_SetTextureBlendMode(texture, sdl.SDL_BLENDMODE_BLEND));

    return .{
        .texture = texture,
        .src = .{ .x = 0, .y = 0, .w = wint, .h = wint },
        .angle = 0,
    };
}
