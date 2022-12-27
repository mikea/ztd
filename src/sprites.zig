const std = @import("std");
const stb = @cImport({
    @cInclude("stb/stb_image.h");
});
const gl = @import("gl.zig");
const model = @import("model.zig");
const Rect = @import("geom.zig").Rect;
const Vec = @import("geom.zig").Vec;
const Shaders = @import("shaders.zig").Shaders;

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

        gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_WRAP_S, gl.c.GL_REPEAT);
        gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_WRAP_T, gl.c.GL_REPEAT);
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
            .angleRad = angle + self.angle,
            .z = z,
        };
    }
};

pub const SpriteRenderer = struct {
    shaders: Shaders,
    vao: gl.c.GLuint,

    pub fn init() !SpriteRenderer {
        var vbo: gl.c.GLuint = 0;
        gl.c.glGenBuffers(1, &vbo);

        var vao: gl.c.GLuint = 0;
        gl.c.glGenVertexArrays(1, &vao);

        const vertices = [_]gl.c.GLfloat{
            // pos      // tex
            0.0, 1.0, 0.0, 1.0,
            1.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 0.0,

            0.0, 1.0, 0.0, 1.0,
            1.0, 1.0, 1.0, 1.0,
            1.0, 0.0, 1.0, 0.0,
        };

        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, vbo);
        defer gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, 0);

        gl.c.glBufferData(gl.c.GL_ARRAY_BUFFER, vertices.len * @sizeOf(gl.c.GLfloat), &vertices, gl.c.GL_STATIC_DRAW);

        gl.c.glBindVertexArray(vao);
        defer gl.c.glBindVertexArray(0);

        gl.c.glEnableVertexAttribArray(0);
        gl.c.glVertexAttribPointer(0, 4, gl.c.GL_FLOAT, gl.c.GL_FALSE, 4 * @sizeOf(gl.c.GLfloat), null);

        return .{
            .shaders = try Shaders.init("shaders/spriteVertex.glsl", "shaders/spriteFragment.glsl"),
            .vao = vao,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.shaders.deinit();
        gl.c.glDeleteVertexArrays(1, &self.vao);
    }

    pub fn startFrame(self: *@This(), displaySize: Vec) void {
        self.shaders.use();
        const mat = [16]gl.c.GLfloat{
            2 / displaySize.x, 0,                 0,  0,
            0,                 2 / displaySize.y, 0,  0,
            0,                 0,                 -1, 0,
            -1,                -1,                0,  1,
        };
        self.shaders.setMatrix4("projection", mat);
        // std.log.debug("displaySize: {} projection: {any}", .{ displaySize, mat });
    }

    pub fn renderSprite(self: *@This(), sprite: *const model.Sprite, destRect: *const Rect) void {
        self.shaders.use();
        const l = destRect.a.x;
        const b = destRect.a.y;
        const r = destRect.b.x;
        const t = destRect.b.y;
        // const pos = destRect.center();
        const modelMat = [16]gl.c.GLfloat{
            r - l, 0,     0,  0,
            0,     t - b, 0,  0,
            0,     0,     -1, 0,
            l,     b,     0,  1,
        };
        self.shaders.setMatrix4("model", modelMat);
        // std.log.debug("destRect: {} model: {any}", .{ destRect, modelMat });
        // glm::mat4 model = glm::mat4(1.0f);
        // model = glm::translate(model, glm::vec3(position, 0.0f));  // first translate (transformations are: scale happens first, then rotation, and then final translation happens; reversed order)

        // model = glm::translate(model, glm::vec3(0.5f * size.x, 0.5f * size.y, 0.0f)); // move origin of rotation to center of quad
        // model = glm::rotate(model, glm::radians(rotate), glm::vec3(0.0f, 0.0f, 1.0f)); // then rotate
        // model = glm::translate(model, glm::vec3(-0.5f * size.x, -0.5f * size.y, 0.0f)); // move origin back

        // model = glm::scale(model, glm::vec3(size, 1.0f)); // last scale

        // this->shader.SetMatrix4("model", model);

        // // render textured quad
        // self.shaders.setVector3f("spriteColor", color);

        gl.c.glActiveTexture(gl.c.GL_TEXTURE0);
        gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, sprite.texture);
        defer gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, 0);

        gl.c.glBindVertexArray(self.vao);
        defer gl.c.glBindVertexArray(0);
        gl.c.glDrawArrays(gl.c.GL_TRIANGLES, 0, 6);
    }
};
