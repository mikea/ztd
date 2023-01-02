const std = @import("std");
const stb = @cImport({
    @cInclude("stb/stb_image.h");
});
const gl = @import("gl.zig");
const model = @import("model.zig");
const Rect = @import("geom.zig").Rect;
const Vec = @import("geom.zig").Vec;
const Program = @import("shaders.zig").Program;
const Viewport = @import("viewport.zig").Viewport;
const rendering = @import("rendering.zig");

pub const SpriteSheet = struct {
    texture: gl.c.GLuint,
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

        var texture: gl.c.GLuint = 0;
        gl.c.glGenTextures(1, &texture);
        gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, texture);
        defer gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, 0);

        gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_WRAP_S, gl.c.GL_CLAMP_TO_EDGE);
        gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_WRAP_T, gl.c.GL_CLAMP_TO_EDGE);
        gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MIN_FILTER, gl.c.GL_NEAREST_MIPMAP_NEAREST);
        gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MAG_FILTER, gl.c.GL_NEAREST_MIPMAP_NEAREST);
        gl.c.glTexImage2D(gl.c.GL_TEXTURE_2D, 0, gl.c.GL_RGBA, width, height, 0, gl.c.GL_RGBA, gl.c.GL_UNSIGNED_BYTE, img);
        gl.c.glGenerateMipmap(gl.c.GL_TEXTURE_2D);

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
        gl.c.glDeleteTextures(1, &self.texture);
    }

    pub fn sprite(self: *const @This(), x: u16, y: u16, angle: f32, z: model.Layer) model.Sprite {
        const sz = Vec.initInt(self.w, self.h).div(Vec.initInt(self.fullWidth, self.fullHeight));

        return .{
            .texture = self.texture,
            .rect = Rect.initSized(Vec.initInt(x, y).mul(sz) , sz),
            .angle = angle + self.angle,
            .z = z,
        };
    }
};

// Renders rectangles with a given shader program.
pub const SpriteRenderer = struct {
    rectRenderer: rendering.RectRenderer,
    program: Program,

    pub fn init() !SpriteRenderer {
        return .{
            .rectRenderer = rendering.RectRenderer.init(),
            .program = try Program.init("shaders/spriteVertex.glsl", "shaders/spriteFragment.glsl"),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.rectRenderer.deinit();
        self.program.deinit();
    }

    pub fn startFrame(self: *@This(), viewport: *Viewport) void {
        self.rectRenderer.startFrame(&self.program, viewport);
    }

    pub fn renderSprite(self: *@This(), sprite: *const model.Sprite, destRect: *const Rect) void {
        self.program.use();

        self.program.setVec2("texScale", sprite.rect.size().asArray());
        self.program.setVec2("texOffset", sprite.rect.a.asArray());

        gl.c.glActiveTexture(gl.c.GL_TEXTURE0);
        gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, sprite.texture);
        defer gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, 0);

        self.rectRenderer.render(&self.program, destRect, sprite.z, sprite.angle);
    }
};
