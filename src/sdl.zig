const std = @import("std");
const model = @import("model.zig");
const cairo = @import("cairo.zig");

pub const c = @cImport({
    @cInclude("SDL.h");
    @cInclude("SDL_image.h");
    @cInclude("SDL_ttf.h");
});

pub const Renderer = c.SDL_Renderer;
pub const Event = c.SDL_Event;

const SdlError = error{
    SdlError,
    ResourceError,
};

pub fn checkInt(i: c_int) void {
    if (i < 0) {
        @panic("SDL Error");
    }
}

pub fn checkNotNull(comptime T: type, ptr: ?*T) *T {
    return ptr orelse @panic("SDL Error");
}

pub const SpriteSheet = struct {
    texture: *c.SDL_Texture,
    w: u16,
    h: u16,
    angleRad: f32,

    pub fn load(renderer: *c.SDL_Renderer, file: [*:0]const u8, w: u16, h: u16, angle: f32) !SpriteSheet {
        const texture = checkNotNull(c.SDL_Texture, c.IMG_LoadTexture(renderer, file));
        return .{ .texture = texture, .w = w, .h = h, .angleRad = angle };
    }

    pub fn deinit(self: @This()) void {
        c.SDL_DestroyTexture(self.texture);
    }

    pub fn sprite(self: *const @This(), x: u16, y: u16, angle: f32, z: model.Layer) model.Sprite {
        return .{ .texture = self.texture, .src = c.SDL_Rect{
            .x = x * self.w,
            .y = y * self.h,
            .w = self.w,
            .h = self.h,
        }, .angleRad = angle + self.angleRad, .z = z };
    }
};

pub const Texture = struct { texture: *c.SDL_Texture, w: i32, h: i32 };

pub fn renderText(
    renderer: *c.SDL_Renderer,
    text: [:0]const u8,
    font: *c.TTF_Font,
    color: c.SDL_Color,
) !Texture {
    const surface = c.TTF_RenderText_Solid_Wrapped(font, @as([*:0]const u8, text), color, 0);
    defer c.SDL_FreeSurface(surface);
    const w = surface.*.w;
    const h = surface.*.h;
    const texture = checkNotNull(c.SDL_Texture, c.SDL_CreateTextureFromSurface(renderer, surface));
    return .{ .texture = texture, .w = w, .h = h };
}

pub fn drawCircle(
    renderer: *c.SDL_Renderer,
    r: f32,
    color: struct { r: f64, g: f64, b: f64, a: f64 },
    style: union(enum) {
        stroke: struct { w: f64 },
        fill: void,
    },
) !Texture {
    const w = r * 2 + 1;
    const wint = @floatToInt(i32, w);
    const texture = checkNotNull(c.SDL_Texture, c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_ARGB8888, c.SDL_TEXTUREACCESS_STREAMING, wint, wint));
    var pitch: c_int = undefined;
    var pixels: [*c]u8 = undefined;
    checkInt(c.SDL_LockTexture(texture, null, @ptrCast([*c]?*anyopaque, &pixels), &pitch));

    const cairoSurface = cairo.c.cairo_image_surface_create_for_data(pixels, cairo.c.CAIRO_FORMAT_ARGB32, wint, wint, pitch);
    const cr = cairo.c.cairo_create(cairoSurface);

    cairo.c.cairo_set_source_rgba(cr, 1, 1, 1, 0);
    cairo.c.cairo_rectangle(cr, 0, 0, w, w);
    cairo.c.cairo_fill(cr);

    cairo.c.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
    cairo.c.cairo_arc(cr, w / 2, w / 2, r, 0, 2 * std.math.pi);
    switch (style) {
        .stroke => |stroke| {
            cairo.c.cairo_set_line_width(cr, stroke.w);
            cairo.c.cairo_stroke(cr);
        },
        .fill => {
            cairo.c.cairo_fill(cr);
        },
    }

    c.SDL_UnlockTexture(texture);

    checkInt(c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND));

    return .{ .texture = texture, .w = wint, .h = wint };
}
