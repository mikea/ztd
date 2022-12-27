const std = @import("std");
pub const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
});
const stb = @cImport({
    @cInclude("stb/stb_image.h");
});
const model = @import("model.zig");
const Rect = @import("geom.zig").Rect;
const Vec = @import("geom.zig").Vec;

pub const SpriteSheet = struct {
    texture: c.GLuint,
    fullWidth: u16,
    fullHeight: u16,
    w: u16,
    h: u16,
    angle: f32,

    pub fn load(comptime fileName: []const u8, w: u16, h: u16, angle: f32) !SpriteSheet {
        return SpriteSheet.loadContent(@embedFile(fileName), w, h, angle);
    }

    fn loadContent(content: []const u8, w: u16, h: u16, angle: f32) !SpriteSheet {
        var width: c_int = 0;
        var height: c_int = 0;
        var ch: c_int = 0;
        const img = stb.stbi_load_from_memory(@ptrCast([*c]const u8, content), @intCast(c_int, content.len), &width, &height, &ch, 4);
        defer stb.stbi_image_free(img);
        std.debug.assert(ch == 4);

        var texture: c.GLuint = 0;
        c.glGenTextures(1, &texture);
        c.glBindTexture(c.GL_TEXTURE_2D, texture);
        defer c.glBindTexture(c.GL_TEXTURE_2D, 0);

        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR_MIPMAP_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, img);
        c.glGenerateMipmap(c.GL_TEXTURE_2D);

        return .{
            .texture = texture,
            .fullWidth = @intCast(u16, width),
            .fullHeight = @intCast(u16, height),
            .w = w,
            .h = h,
            .angle = angle,
        };
    }

    pub fn deinit(self: *@This()) void {
        c.glDeleteTextures(1, &self.texture);
    }

    pub fn sprite(self: *const @This(), x: u16, y: u16, angle: f32, z: model.Layer) model.Sprite {
        return .{
            .texture = self.texture,
            .src = Rect.initSized(Vec.initInt(x * self.w, y * self.h), Vec.initInt(self.w, self.h)),
            .angleRad = angle + self.angle,
            .z = z,
        };
    }
};

