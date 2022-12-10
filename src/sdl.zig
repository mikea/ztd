const std = @import("std");

const model = @import("model.zig");

pub const c = @cImport({
    @cInclude("SDL.h");
    @cInclude("SDL_image.h");
    @cInclude("SDL_ttf.h");
});

const cairo = @cImport({
    @cInclude("cairo.h");
});

pub const Renderer = c.SDL_Renderer;
pub const Event = c.SDL_Event;

const SdlError = error{
    SdlError,
    ResourceError,
};

pub fn checkInt(i: c_int) !void {
    if (i < 0) {
        return SdlError.SdlError;
    }
}

pub fn checkNotNull(comptime T: type, ptr: ?*T) !*T {
    return ptr orelse SdlError.SdlError;
}

pub const SpriteSheet = struct {
    texture: *c.SDL_Texture,
    w: u16,
    h: u16,

    pub fn load(renderer: *c.SDL_Renderer, file: [*:0]const u8, w: u16, h: u16) !SpriteSheet {
        const texture = checkNotNull(c.SDL_Texture, c.IMG_LoadTexture(renderer, file)) catch {
            std.log.err("failed to load {s}", .{file});
            return SdlError.ResourceError;
        };
        return .{ .texture = texture, .w = w, .h = h };
    }

    pub fn deinit(self: @This()) void {
        c.SDL_DestroyTexture(self.texture);
    }

    pub fn sprite(self: *const @This(), x: u16, y: u16, angle: f64, z: model.Layer) model.Sprite {
        return .{ .texture = self.texture, .src = c.SDL_Rect{
            .x = x * self.w,
            .y = y * self.h,
            .w = self.w,
            .h = self.h,
        }, .angle = angle, .z = z };
    }
};

pub fn drawCircle(
    renderer: *c.SDL_Renderer,
    r: f32,
    color: struct { r: f64, g: f64, b: f64, a: f64 },
    style: union(enum) {
        stroke: struct { w: f64 },
        fill: void,
    },
) !struct { texture: *c.SDL_Texture, w: i32, h: i32 } {
    const w = r * 2 + 1;
    const wint = @floatToInt(i32, w);
    const texture = try checkNotNull(c.SDL_Texture, c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_ARGB8888, c.SDL_TEXTUREACCESS_STREAMING, wint, wint));
    var pitch: c_int = undefined;
    var pixels: [*c]u8 = undefined;
    try checkInt(c.SDL_LockTexture(texture, null, @ptrCast([*c]?*anyopaque, &pixels), &pitch));

    const cairoSurface = cairo.cairo_image_surface_create_for_data(pixels, cairo.CAIRO_FORMAT_ARGB32, wint, wint, pitch);
    const cr = cairo.cairo_create(cairoSurface);

    cairo.cairo_set_source_rgba(cr, 1, 1, 1, 0);
    cairo.cairo_rectangle(cr, 0, 0, w, w);
    cairo.cairo_fill(cr);

    cairo.cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
    cairo.cairo_arc(cr, w / 2, w / 2, r, 0, 2 * std.math.pi);
    switch (style) {
        .stroke => |stroke| {
            cairo.cairo_set_line_width(cr, stroke.w);
            cairo.cairo_stroke(cr);
        },
        .fill => {
            cairo.cairo_fill(cr);
        },
    }

    c.SDL_UnlockTexture(texture);

    try checkInt(c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND));

    return .{ .texture = texture, .w = wint, .h = wint };
}
