const std = @import("std");
const gl = @import("gl.zig");

const Error = error{ShaderError};

pub fn Program(comptime Uniforms: type) type {
    const locSize = @typeInfo(Uniforms).Enum.fields.len;

    return struct {
        program: gl.c.GLuint,
        vertex: gl.c.GLuint,
        fragment: gl.c.GLuint,
        locs: [locSize]gl.c.GLint,

        pub fn init(comptime vertexSource: []const u8, comptime fragmentSource: []const u8) !@This() {
            const vertex = try compileShaderFile(gl.c.GL_VERTEX_SHADER, vertexSource);
            const fragment = try compileShaderFile(gl.c.GL_FRAGMENT_SHADER, fragmentSource);

            const program = gl.c.glCreateProgram();
            gl.c.glAttachShader(program, vertex);
            gl.c.glAttachShader(program, fragment);
            gl.c.glLinkProgram(program);
            try checkShaderStatus(program, gl.c.GL_LINK_STATUS);

            var locs: [locSize]gl.c.GLint = undefined;
            inline for (@typeInfo(Uniforms).Enum.fields) |field| {
                locs[field.value] = gl.c.glGetUniformLocation(program, @ptrCast([*c]const u8, field.name));
            }

            return .{
                .program = program,
                .vertex = vertex,
                .fragment = fragment,
                .locs = locs,
            };
        }

        pub fn deinit(self: *@This()) void {
            gl.c.glDeleteShader(self.vertex);
            gl.c.glDeleteShader(self.fragment);
        }

        pub fn use(self: *const @This()) void {
            gl.c.glUseProgram(self.program);
        }

        pub fn setMatrix4(self: *const @This(), comptime uniform: Uniforms, mat: [16]gl.c.GLfloat) void {
            gl.c.glUniformMatrix4fv(self.locs[@enumToInt(uniform)], 1, 0, &mat);
        }

        pub fn setVec2(self: *const @This(), comptime uniform: Uniforms, vec: [2]gl.c.GLfloat) void {
            gl.c.glUniform2fv(self.locs[@enumToInt(uniform)], 1, &vec);
        }

        pub fn setFloat(self: *const @This(), comptime uniform: Uniforms, f: gl.c.GLfloat) void {
            gl.c.glUniform1f(self.locs[@enumToInt(uniform)], f);
        }
    };
}

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
