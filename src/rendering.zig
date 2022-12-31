const std = @import("std");
const gl = @import("gl.zig");
const Program = @import("shaders.zig").Program;
const Viewport = @import("viewport.zig").Viewport;
const Rect = @import("geom.zig").Rect;
const Vec = @import("geom.zig").Vec;
const model = @import("model.zig");

// Renders rectangles in a game space with a given shader program.
pub const RectRenderer = struct {
    vao: gl.c.GLuint,

    pub fn init() RectRenderer {
        gl.c.glEnable(gl.c.GL_BLEND);
        gl.c.glBlendFunc(gl.c.GL_SRC_ALPHA, gl.c.GL_ONE_MINUS_SRC_ALPHA);

        gl.c.glEnable(gl.c.GL_DEPTH_TEST);

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

        return .{ .vao = vao };
    }

    pub fn deinit(self: *@This()) void {
        gl.c.glDeleteVertexArrays(1, &self.vao);
    }

    pub fn startFrame(_: *@This(), program: *Program, viewport: *Viewport) void {
        program.use();
        program.setMatrix4("projection", viewport.mat);
    }

    pub fn render(self: *@This(), program: *Program, destRect: *const Rect, layer: model.Layer, angle: f32) void {
        program.use();
        const l = destRect.a.x;
        const b = destRect.a.y;
        const w = destRect.b.x - l;
        const h = destRect.b.y - b;
        const cos = if (angle != 0) std.math.cos(angle) else 1;
        const sin = if (angle != 0) std.math.sin(angle) else 0;
        const z = -@intToFloat(f32, @enumToInt(layer)) / @intToFloat(f32, @typeInfo(model.Layer).Enum.fields.len) ;

        // RotationTransform[theta, {l + w/2, b + h/2}].
        // TranslationTransform[{l, b}] .
        // ScalingTransform[{w, h}]
        const modelMat = [16]gl.c.GLfloat{
            w * cos,                           w * sin,                           0, 0,
            -h * sin,                          h * cos,                           0, 0,
            0,                                 0,                                 1, 0,
            l + 0.5 * (w - w * cos + h * sin), b + 0.5 * (h - h * cos - w * sin), z, 1,
        };
        program.setMatrix4("model", modelMat);

        gl.c.glBindVertexArray(self.vao);
        defer gl.c.glBindVertexArray(0);
        gl.c.glDrawArrays(gl.c.GL_TRIANGLES, 0, 6);
    }
};


// Renders rectangles with a given shader program.
pub const HealthRenderer = struct {
    rectRenderer: RectRenderer,
    program: Program,

    pub fn init() !HealthRenderer {
        return .{
            .rectRenderer = RectRenderer.init(),
            .program = try Program.init("shaders/healthVertex.glsl", "shaders/healthFragment.glsl"),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.rectRenderer.deinit();
        self.program.deinit();
    }

    pub fn startFrame(self: *@This(), viewport: *Viewport) void {
        self.rectRenderer.startFrame(&self.program, viewport);
    }

    pub fn renderHealth(self: *@This(), health: f32, destRect: *const Rect) void {
        self.program.use();
        self.program.setFloat("h", health);
        self.rectRenderer.render(&self.program, destRect, .MONSTER, 0);
    }
};
