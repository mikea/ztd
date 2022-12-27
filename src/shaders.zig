const std = @import("std");
const gl = @import("gl.zig");

const Error = error{ ShaderError };

pub const Shaders = struct {
    program: gl.c.GLuint,
    vertex: gl.c.GLuint,
    fragment: gl.c.GLuint,

    pub fn init(comptime vertexSource: []const u8, comptime fragmentSource: []const u8) !Shaders {
        const vertex = try compileShaderFile(gl.c.GL_VERTEX_SHADER, vertexSource);
        const fragment = try compileShaderFile(gl.c.GL_FRAGMENT_SHADER, fragmentSource);

        const program = gl.c.glCreateProgram();
        gl.c.glAttachShader(program, vertex);
        gl.c.glAttachShader(program, fragment);
        gl.c.glLinkProgram(program);
        try checkShaderStatus(program, gl.c.GL_LINK_STATUS);

        return .{
            .program = program,
            .vertex = vertex,
            .fragment = fragment,
        };
    }

    pub fn deinit(self: *@This()) void {
        gl.c.glDeleteShader(self.vertex);
        gl.c.glDeleteShader(self.fragment);
    }

    pub fn use(self: *const @This()) void {
        gl.c.glUseProgram(self.program);
    }

    pub fn setMatrix4(self: *const @This(), name: []const u8, mat: [16]gl.c.GLfloat) void {
        const loc = gl.c.glGetUniformLocation(self.program, @ptrCast([*c]const u8, name));
        gl.c.glUniformMatrix4fv(loc, 1, 0, &mat);
    }
};

fn compileShaderFile(comptime t: gl.c.GLenum, comptime fileName: []const u8) !gl.c.GLuint {
    return compileShaderContent(t, @embedFile(fileName)) catch |err| {
        std.log.err("Error while loading {s}", .{fileName});
        return err;
    };
}

fn compileShaderContent(t: gl.c.GLenum, content: [*c]const u8) !gl.c.GLuint {
    const shader = gl.c.glCreateShader(t);
    gl.c.glShaderSource(shader, 1, &content, null);
    gl.c.glCompileShader(shader);
    try checkShaderStatus(shader, gl.c.GL_COMPILE_STATUS);
    return shader;
}

fn checkShaderStatus(shader: gl.c.GLuint, status: gl.c.GLenum) !void {
    var success: gl.c.GLint = 1;
    gl.c.glGetShaderiv(shader, status, &success);
    if (success == 1) {
        return;
    }

    var infoLog: [1024]u8 = undefined;
    gl.c.glGetShaderInfoLog(shader, infoLog.len, null, &infoLog);
    std.log.err("GLSL ERROR: {} {s}", .{ gl.c.glGetError(), @ptrCast([*:0]const u8, &infoLog) });
    return Error.ShaderError;
}
