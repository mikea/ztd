const std = @import("std");
const builtin = @import("builtin");
const gl = @import("gl.zig");
const rendering = @import("rendering.zig");
const Program = @import("shaders.zig").Program;
const Viewport = @import("viewport.zig").Viewport;
const Rect = @import("geom.zig").Rect;
const Vec = @import("geom.zig").Vec;
const model = @import("model.zig");

pub const c = @cImport({
    @cInclude("stb/stb_rect_pack.h");
    @cInclude("stb/stb_truetype.h");
    @cInclude("stb/stb_image_write.h");
});

const Error = error{GenericError};

fn checkCBool(i: c_int) !void {
    if (i == 0) {
        return Error.GenericError;
    }
}

pub const FontInfo = struct {
    fi: c.stbtt_fontinfo,
    texture: gl.c.GLuint,
    chars: []const c.stbtt_packedchar,

    pub fn init(allocator: std.mem.Allocator, fontContent: [*c]const u8) !FontInfo {
        var fi: c.stbtt_fontinfo = undefined;
        try checkCBool(c.stbtt_InitFont(&fi, fontContent, 0));
        const atlas = try buildAtlas(allocator, &fi, fontContent);
        return .{ .fi = fi, .texture = atlas.texture, .chars = atlas.chars };
    }

    pub fn deinit(self: *FontInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.chars);
    }

    pub fn bounds(self: *const FontInfo, text: []const u8, pixelHeight: f32) Vec {
        const scale = c.stbtt_ScaleForPixelHeight(&self.fi, pixelHeight);

        var x: c_int = 0;
        for (text) |ch, i| {
            var w: c_int = 0;
            var lsb: c_int = 0;
            c.stbtt_GetCodepointHMetrics(&self.fi, ch, &w, &lsb);
            x += scaleInt(w, scale);

            if (i + 1 < text.len) {
                var kern = c.stbtt_GetCodepointKernAdvance(&self.fi, ch, text[i + 1]);
                x += scaleInt(kern, scale);
            }
        }

        return Vec.init(x, pixelHeight);
    }

    pub fn renderTexture(self: *const FontInfo, text: []const u8, pixelHeight: f32, allocator: std.mem.Allocator) !struct {
        texture: gl.c.GLuint,
        w: usize,
        h: usize,
    } {
        const b = self.bounds(text, pixelHeight);
        var bitmap = try allocator.alloc(u8, @intCast(usize, b.w * b.h));
        std.mem.set(u8, bitmap, 0);
        defer allocator.free(bitmap);

        const scale = c.stbtt_ScaleForPixelHeight(&self.fi, pixelHeight);

        var ascent: c_int = 0;
        c.stbtt_GetFontVMetrics(&self.fi, &ascent, null, null);
        ascent = scaleInt(ascent, scale);

        var x: c_int = 0;
        for (text) |ch, i| {
            var w: c_int = 0;
            var lsb: c_int = 0;
            c.stbtt_GetCodepointHMetrics(&self.fi, ch, &w, &lsb);
            w = scaleInt(w, scale);
            lsb = scaleInt(lsb, scale);

            var x1: c_int = undefined;
            var x2: c_int = undefined;
            var y1: c_int = undefined;
            var y2: c_int = undefined;
            c.stbtt_GetCodepointBitmapBox(&self.fi, ch, scale, scale, &x1, &y1, &x2, &y2);
            const y = ascent + y1;

            var offset = @intCast(usize, x + lsb + y * b.w);
            c.stbtt_MakeCodepointBitmap(&self.fi, bitmap[offset..].ptr, x2 - x1, y2 - y1, b.w, scale, scale, ch);

            x += w;
            if (i + 1 < text.len) {
                var kern = c.stbtt_GetCodepointKernAdvance(&self.fi, ch, text[i + 1]);
                x += scaleInt(kern, scale);
            }
        }

        var texture: gl.c.GLuint = 0;
        gl.c.glGenTextures(1, &texture);
        gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, texture);
        defer gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, 0);

        gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_WRAP_S, gl.c.GL_CLAMP_TO_EDGE);
        gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_WRAP_T, gl.c.GL_CLAMP_TO_EDGE);
        gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MIN_FILTER, gl.c.GL_NEAREST_MIPMAP_NEAREST);
        gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MAG_FILTER, gl.c.GL_NEAREST_MIPMAP_NEAREST);
        gl.c.glTexImage2D(gl.c.GL_TEXTURE_2D, 0, gl.c.GL_RGBA, b.w, b.h, 0, gl.c.GL_RED, gl.c.GL_UNSIGNED_BYTE, bitmap.ptr);
        gl.c.glGenerateMipmap(gl.c.GL_TEXTURE_2D);
        const swizzle = comptime [_]u32{ gl.c.GL_ZERO, gl.c.GL_ZERO, gl.c.GL_ZERO, gl.c.GL_RED };
        gl.c.glTexParameteriv(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_SWIZZLE_RGBA, @ptrCast([*c]const i32, &swizzle));

        return .{ .texture = texture, .w = @intCast(usize, b.w), .h = @intCast(usize, b.h) };
    }
};

fn printBitmap(bitmap: []const u8, w: usize, h: usize) void {
    var j: usize = 0;
    while (j < h) : (j += 1) {
        var i: usize = 0;
        while (i < w) : (i += 1) {
            std.debug.print("{d:3} ", .{bitmap[i + j * w]});
        }
        std.debug.print("\n", .{});
    }
}

fn scaleInt(i: c_int, s: f32) c_int {
    return @floatToInt(c_int, @round(@intToFloat(f32, i) * s));
}

const atlasDim = 256;

fn buildAtlas(allocator: std.mem.Allocator, fontInfo: *c.stbtt_fontinfo, fontContent: [*c]const u8) !struct {
    texture: gl.c.GLuint,
    chars: []const c.stbtt_packedchar,
} {
    try std.io.getStdOut().writer().print("building font atlas...", .{});
    const atlas_row_size = atlasDim;
    var atlas = try allocator.alloc(u8, atlas_row_size * atlasDim);
    defer allocator.free(atlas);
    std.mem.set(u8, atlas, 0);

    // const scale = c.stbtt_ScaleForPixelHeight(fontInfo, 30);
    _ = fontInfo;
    const scale = 30;

    var pc: c.stbtt_pack_context = undefined;
    try checkCBool(c.stbtt_PackBegin(&pc, atlas.ptr, atlasDim, atlasDim, atlas_row_size, 1, null));
    const first_char = 32;
    const num_chars = 120;
    var char_data = try allocator.alloc(c.stbtt_packedchar, num_chars);
    try checkCBool(c.stbtt_PackFontRange(&pc, fontContent, 0, scale, first_char, num_chars, char_data.ptr));
    c.stbtt_PackEnd(&pc);

    if (builtin.mode == .Debug) {
        if (c.stbi_write_png("/tmp/fontAtlas.png", atlasDim, atlasDim, 1, atlas.ptr, atlas_row_size) != 1) {
            @panic("error writing font atlas");
        }
    }

    var texture: gl.c.GLuint = 0;
    gl.c.glGenTextures(1, &texture);
    gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, texture);
    defer gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, 0);
    gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MIN_FILTER, gl.c.GL_LINEAR);
    gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MAG_FILTER, gl.c.GL_LINEAR);
    gl.c.glTexImage2D(gl.c.GL_TEXTURE_2D, 0, gl.c.GL_RED, atlasDim, atlasDim, 0, gl.c.GL_RED, gl.c.GL_UNSIGNED_BYTE, atlas.ptr);
    // gl.c.glGenerateMipmap(gl.c.GL_TEXTURE_2D);

    try std.io.getStdOut().writer().print("done.\n", .{});
    return .{ .texture = texture, .chars = char_data };
}

pub const TextRenderer = struct {
    const Uniforms = enum { model, projection, texRect, textColor };
    rectRenderer: rendering.RectRenderer,
    program: Program(Uniforms),

    pub fn init() !TextRenderer {
        return .{
            .rectRenderer = rendering.RectRenderer.init(),
            .program = try Program(Uniforms).init("shaders/fontVertex.glsl", "shaders/fontFragment.glsl"),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.rectRenderer.deinit();
        self.program.deinit();
    }

    pub fn startFrame(self: *@This(), viewport: *Viewport) void {
        self.rectRenderer.startFrame(&self.program, viewport);
    }

    pub fn render(self: *@This(), destRect: Rect, text: *const model.Text) void {
        self.program.use();
        var x: f32 = 0;
        var y: f32 = 0;
        const scale = destRect.size().y / 30.0;

        gl.c.glActiveTexture(gl.c.GL_TEXTURE0);
        gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, text.font.texture);
        defer gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, 0);

        std.log.debug("***** {} {}", .{ destRect, scale });
        for (text.str) |ch| {
            var quad: c.stbtt_aligned_quad = undefined;
            c.stbtt_GetPackedQuad(text.font.chars.ptr, atlasDim, atlasDim, ch, &x, &y, &quad, 1);
            const rect = Rect.init(destRect.a.x + scale*quad.x0, destRect.a.y + scale*quad.y0, destRect.a.x + scale*quad.x1, destRect.a.y + scale*quad.y1);
            self.program.setVec4(.texRect, [4]f32{quad.s0, quad.t0, quad.s1, quad.t1});
            self.program.setVec4(.textColor, text.color);
            self.rectRenderer.render(&self.program, rect, text.layer, 0);
        }
    }
};
