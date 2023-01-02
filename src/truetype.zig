const std = @import("std");
const gl = @import("gl.zig");


pub const c = @cImport({
    @cInclude("stb/stb_truetype.h");
});

const Error = error{GenericError};

fn checkCBool(i: c_int) !void {
    if (i == 0) {
        return Error.GenericError;
    }
}

const rubikMonoOne = @embedFile("res/RubikMonoOne-Regular.ttf");

const FontInfo = struct {
    fi: c.stbtt_fontinfo,

    pub fn init(fontContent: [*c]const u8) !FontInfo {
        var fi: c.stbtt_fontinfo = undefined;
        try checkCBool(c.stbtt_InitFont(&fi, fontContent, 0));
        return .{ .fi = fi };
    }

    pub fn bounds(self: *const FontInfo, text: []const u8, pixelHeight: f32) struct { w: c_int, h: c_int } {
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

        return .{ .w = x, .h = @floatToInt(c_int, @ceil(pixelHeight)) };
    }
};

fn scaleInt(i: c_int, s: f32) c_int {
    return @floatToInt(c_int, @round(@intToFloat(f32, i) * s));
}

pub fn renderText(text: []const u8, pixelHeight: f32, allocator: std.mem.Allocator) !struct {
    texture: gl.c.GLuint,
    w: usize,
    h: usize,
} {
    const fontInfo = try FontInfo.init(rubikMonoOne);
    const bounds = fontInfo.bounds(text, pixelHeight);
    var bitmap = try allocator.alloc(u8, @intCast(usize, bounds.w * bounds.h));
    defer allocator.free(bitmap);

    const scale = c.stbtt_ScaleForPixelHeight(&fontInfo.fi, pixelHeight);

    var ascent: c_int = 0;
    c.stbtt_GetFontVMetrics(&fontInfo.fi, &ascent, null, null);
    ascent = scaleInt(ascent, scale);

    var x: c_int = 0;
    for (text) |ch, i| {
        var w: c_int = 0;
        var lsb: c_int = 0;
        c.stbtt_GetCodepointHMetrics(&fontInfo.fi, ch, &w, &lsb);
        w = scaleInt(w, scale);
        lsb = scaleInt(lsb, scale);

        var x1: c_int = undefined;
        var x2: c_int = undefined;
        var y1: c_int = undefined;
        var y2: c_int = undefined;
        c.stbtt_GetCodepointBitmapBox(&fontInfo.fi, ch, scale, scale, &x1, &y1, &x2, &y2);
        const y = ascent + y1;

        var offset = @intCast(usize, x + lsb + y * bounds.w);
        c.stbtt_MakeCodepointBitmap(&fontInfo.fi, bitmap[offset..].ptr, x2 - x1, y2 - y1, bounds.w, scale, scale, ch);

        x += w;
        if (i + 1 < text.len) {
            var kern = c.stbtt_GetCodepointKernAdvance(&fontInfo.fi, ch, text[i + 1]);
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
    gl.c.glTexImage2D(gl.c.GL_TEXTURE_2D, 0, gl.c.GL_R8, bounds.w, bounds.h, 0, gl.c.GL_RED, gl.c.GL_UNSIGNED_BYTE, bitmap.ptr);
    gl.c.glGenerateMipmap(gl.c.GL_TEXTURE_2D);

    return .{ .texture = texture, .w = @intCast(usize, bounds.w), .h = @intCast(usize, bounds.h) };
}
