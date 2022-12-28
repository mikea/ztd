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
        gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MIN_FILTER, gl.c.GL_LINEAR_MIPMAP_LINEAR);
        gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MAG_FILTER, gl.c.GL_LINEAR);
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
        return .{
            .texture = self.texture,
            .src = Rect.initSized(Vec.initInt(x * self.w, y * self.h), Vec.initInt(self.w, self.h)),
            .angle = angle + self.angle,
            .z = z,
            .sheet = self,
        };
    }
};

pub const SpriteRenderer = struct {
    program: Program,
    vao: gl.c.GLuint,

    pub fn init() !SpriteRenderer {
        gl.c.glEnable(gl.c.GL_BLEND);
        gl.c.glBlendFunc(gl.c.GL_SRC_ALPHA, gl.c.GL_ONE_MINUS_SRC_ALPHA);

        var vbo: gl.c.GLuint = 0;
        gl.c.glGenBuffers(1, &vbo);

        var vao: gl.c.GLuint = 0;
        gl.c.glGenVertexArrays(1, &vao);

        // y axis of texture is flipped to account for flipped images when loaded
        const vertices = [_]gl.c.GLfloat{
            // pos    // tex
            0.0, 1.0, 0.0, 0.0,
            1.0, 0.0, 1.0, 1.0,
            0.0, 0.0, 0.0, 1.0,

            0.0, 1.0, 0.0, 0.0,
            1.0, 1.0, 1.0, 0.0,
            1.0, 0.0, 1.0, 1.0,
        };

        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, vbo);
        defer gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, 0);

        gl.c.glBufferData(gl.c.GL_ARRAY_BUFFER, vertices.len * @sizeOf(gl.c.GLfloat), &vertices, gl.c.GL_STATIC_DRAW);

        gl.c.glBindVertexArray(vao);
        defer gl.c.glBindVertexArray(0);

        gl.c.glEnableVertexAttribArray(0);
        gl.c.glVertexAttribPointer(0, 4, gl.c.GL_FLOAT, gl.c.GL_FALSE, 4 * @sizeOf(gl.c.GLfloat), null);

        return .{
            .program = try Program.init("shaders/spriteVertex.glsl", "shaders/spriteFragment.glsl"),
            .vao = vao,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.program.deinit();
        gl.c.glDeleteVertexArrays(1, &self.vao);
    }

    pub fn startFrame(self: *@This(), viewport: *Viewport) void {
        self.program.use();
        self.program.setMatrix4("projection", viewport.mat);
    }

    pub fn renderSprite(self: *@This(), sprite: *const model.Sprite, destRect: *const Rect) void {
        self.program.use();
        const l = destRect.a.x;
        const b = destRect.a.y;
        const w = destRect.b.x - l;
        const h = destRect.b.y - b;
        const cos = if (sprite.angle != 0) std.math.cos(sprite.angle) else 1;
        const sin = if (sprite.angle != 0) std.math.sin(sprite.angle) else 0;

        // RotationTransform[theta, {l + w/2, b + h/2}].
        // TranslationTransform[{l, b}] .
        // ScalingTransform[{w, h}]

        const modelMat = [16]gl.c.GLfloat{
            w * cos,                           w * sin,                           0, 0,
            -h * sin,                          h * cos,                           0, 0,
            0,                                 0,                                 1, 0,
            l + 0.5 * (w - w * cos + h * sin), b + 0.5 * (h - h * cos - w * sin), 0, 1,
        };
        self.program.setMatrix4("model", modelMat);
        const size = sprite.src.size();
        const texScale = [2]gl.c.GLfloat{
            size.x / @intToFloat(gl.c.GLfloat, sprite.sheet.fullWidth),
            size.y / @intToFloat(gl.c.GLfloat, sprite.sheet.fullHeight),
        };
        const texOffset = [2]gl.c.GLfloat{
            sprite.src.a.x / @intToFloat(gl.c.GLfloat, sprite.sheet.fullWidth),
            sprite.src.a.y / @intToFloat(gl.c.GLfloat, sprite.sheet.fullHeight),
        };
        self.program.setVec2("texScale", texScale);
        self.program.setVec2("texOffset", texOffset);

        gl.c.glActiveTexture(gl.c.GL_TEXTURE0);
        gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, sprite.texture);
        defer gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, 0);

        gl.c.glBindVertexArray(self.vao);
        defer gl.c.glBindVertexArray(0);
        gl.c.glDrawArrays(gl.c.GL_TRIANGLES, 0, 6);
    }
};
