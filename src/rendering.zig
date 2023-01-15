const std = @import("std");
const gl = @import("gl.zig");
const Program = @import("shaders.zig").Program;
const Viewport = @import("viewport.zig").Viewport;
const Rect = @import("geom.zig").Rect;
const Vec = @import("geom.zig").Vec;
const model = @import("model.zig");

// y axis of texture is flipped to account for flipped images when loaded
const quadVertices = [_]gl.c.GLfloat{
    // pos    // tex
    0.0, 1.0, 0.0, 0.0,
    1.0, 0.0, 1.0, 1.0,
    0.0, 0.0, 0.0, 1.0,

    0.0, 1.0, 0.0, 0.0,
    1.0, 1.0, 1.0, 0.0,
    1.0, 0.0, 1.0, 1.0,
};

// Renders rectangles in a game space with a given shader program.
pub const RectRenderer = struct {
    vao: gl.c.GLuint,

    pub fn init() RectRenderer {
        gl.c.glEnable(gl.c.GL_BLEND);
        gl.c.glBlendFunc(gl.c.GL_SRC_ALPHA, gl.c.GL_ONE_MINUS_SRC_ALPHA);

        gl.c.glEnable(gl.c.GL_DEPTH_TEST);

        const vbo = gl.genBuffer();

        var vao: gl.c.GLuint = 0;
        gl.c.glGenVertexArrays(1, &vao);

        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, vbo);
        defer gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, 0);
        gl.c.glBufferData(gl.c.GL_ARRAY_BUFFER, quadVertices.len * @sizeOf(gl.c.GLfloat), &quadVertices, gl.c.GL_STATIC_DRAW);

        gl.c.glBindVertexArray(vao);
        defer gl.c.glBindVertexArray(0);

        gl.c.glEnableVertexAttribArray(0);
        gl.c.glVertexAttribPointer(0, 4, gl.c.GL_FLOAT, gl.c.GL_FALSE, 4 * @sizeOf(gl.c.GLfloat), null);

        return .{ .vao = vao };
    }

    pub fn deinit(self: *@This()) void {
        gl.c.glDeleteVertexArrays(1, &self.vao);
    }

    pub fn startFrame(_: *@This(), program: anytype, viewport: *Viewport) void {
        program.use();
        program.setMatrix4(.projection, viewport.mat);
    }

    pub fn render(self: *@This(), program: anytype, destRect: Rect, layer: model.Layer, angle: f32) void {
        program.use();
        program.setMatrix4(.model, modelMat(destRect, layer, angle));

        gl.c.glBindVertexArray(self.vao);
        defer gl.c.glBindVertexArray(0);
        gl.c.glDrawArrays(gl.c.GL_TRIANGLES, 0, 6);
    }
};

pub fn modelMat(rect: Rect, layer: model.Layer, angle: f32) [16]gl.c.GLfloat {
    const l = rect.a.x;
    const b = rect.a.y;
    const w = rect.b.x - l;
    const h = rect.b.y - b;
    const cos = if (angle != 0) std.math.cos(angle) else 1;
    const sin = if (angle != 0) std.math.sin(angle) else 0;
    const z = -@intToFloat(f32, @enumToInt(layer)) / @intToFloat(f32, @typeInfo(model.Layer).Enum.fields.len);

    // RotationTransform[theta, {l + w/2, b + h/2}].
    // TranslationTransform[{l, b}] .
    // ScalingTransform[{w, h}]
    return [16]gl.c.GLfloat{
        w * cos,                           w * sin,                           0, 0,
        -h * sin,                          h * cos,                           0, 0,
        0,                                 0,                                 1, 0,
        l + 0.5 * (w - w * cos + h * sin), b + 0.5 * (h - h * cos - w * sin), z, 1,
    };
}

pub const HealthRenderer = struct {
    const Uniforms = enum { model, projection, h };
    rectRenderer: RectRenderer,
    program: Program(Uniforms),

    pub fn init() !HealthRenderer {
        return .{
            .rectRenderer = RectRenderer.init(),
            .program = try Program(Uniforms).init("shaders/healthVertex.glsl", "shaders/healthFragment.glsl"),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.rectRenderer.deinit();
        self.program.deinit();
    }

    pub fn startFrame(self: *@This(), viewport: *Viewport) void {
        self.rectRenderer.startFrame(&self.program, viewport);
    }

    pub fn renderHealth(self: *@This(), destRect: Rect, health: f32) void {
        self.program.use();
        self.program.setFloat(.h, health);
        self.rectRenderer.render(&self.program, destRect, .MONSTER, 0);
    }
};

pub const GeometryRenderer = struct {
    const Uniforms = enum { model, projection, geomColor };
    rectRenderer: RectRenderer,
    program: Program(Uniforms),

    pub fn init() !GeometryRenderer {
        return .{
            .rectRenderer = RectRenderer.init(),
            .program = try Program(Uniforms).init("shaders/geometryVertex.glsl", "shaders/geometryFragment.glsl"),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.rectRenderer.deinit();
        self.program.deinit();
    }

    pub fn startFrame(self: *@This(), viewport: *Viewport) void {
        self.rectRenderer.startFrame(&self.program, viewport);
    }

    pub fn render(self: *@This(), destRect: Rect, geometry: *const model.Geometry) void {
        self.program.use();
        self.program.setVec4(.geomColor, geometry.color);
        self.rectRenderer.render(&self.program, destRect, geometry.layer, 0);
    }
};
