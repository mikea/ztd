const std = @import("std");
const builtin = @import("builtin");
const gl = @import("gl.zig");
const c = gl.c;
const Resources = @import("resources.zig").Resources;
const Engine = @import("engine.zig").Engine;
const Game = @import("game.zig").Game;
const levels = @import("levels.zig");

const imgui = @cImport({
    @cInclude("stdlib.h");
    @cInclude("stdarg.h");
    @cInclude("cimgui/cimgui.h");
});

const Error = error{ GenericError, NullPointer, ShaderError };

pub fn checkCBool(i: c_int) !void {
    if (i == 0) {
        return Error.GenericError;
    }
}

pub fn checkBool(b: bool) !void {
    if (!b) {
        return Error.GenericError;
    }
}

fn onError(err: c_int, desc: ?[*:0]const u8) callconv(.C) void {
    std.log.err("glfw error {}: {any}\n", .{ err, desc });
}

// ---------------------------------------------------------------------------------------------
fn framebufferSizeCallback(_: ?*c.GLFWwindow, width: c.GLint, height: c.GLint) callconv(.C) void {
    std.log.err("new size: {}x{}", .{width, height});
    c.glViewport(0, 0, width, height);
}

fn Required(comptime t: type) type {
    const info = @typeInfo(t);
    return switch (info) {
        .Optional => |o| o.child,
        else => @compileError("Optional type expected"),
    };
}
fn checkNotNull(ptr: anytype) !Required(@TypeOf(ptr)) {
    return ptr orelse Error.NullPointer;
}

fn onKey(window: ?*c.GLFWwindow, key: c_int, _: c_int, action: c_int, _: c_int) callconv(.C) void {
    std.log.debug("onKey: {}", .{key});
    if (key == c.GLFW_KEY_Q and action == c.GLFW_PRESS) {
        c.glfwSetWindowShouldClose(window, 1);
    }
}

extern fn ImGui_ImplOpenGL3_Init(glslVersion: [*c]const u8) bool;
extern fn ImGui_ImplGlfw_InitForOpenGL(window: *c.GLFWwindow, installCallbacks: bool) bool;
extern fn ImGui_ImplOpenGL3_NewFrame() void;
extern fn ImGui_ImplGlfw_NewFrame() void;
extern fn ImGui_ImplOpenGL3_RenderDrawData(data: *imgui.ImDrawData) void;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const leaked = gpa.deinit();
        if (leaked) @panic("Memory Leak Detected");
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    _ = c.glfwSetErrorCallback(onError);
    try checkCBool(c.glfwInit());
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 4);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
    if (builtin.os.tag == .macos) {
        c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GL_TRUE);
    }

    const monitor = try checkNotNull(c.glfwGetPrimaryMonitor());
    const mode = c.glfwGetVideoMode(monitor);

    c.glfwWindowHint(c.GLFW_RED_BITS, mode.*.redBits);
    c.glfwWindowHint(c.GLFW_GREEN_BITS, mode.*.greenBits);
    c.glfwWindowHint(c.GLFW_BLUE_BITS, mode.*.blueBits);
    c.glfwWindowHint(c.GLFW_REFRESH_RATE, mode.*.refreshRate);

    const window = try checkNotNull(c.glfwCreateWindow(mode.*.width, mode.*.height, "My Window", monitor, null));
    defer c.glfwDestroyWindow(window);

    c.glfwMakeContextCurrent(window);
    _ = c.glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);

    try checkCBool(c.gladLoadGLLoader(@ptrCast(c.GLADloadproc, &c.glfwGetProcAddress)));

    // const imguiCtx = try checkNotNull(imgui.ImGui_CreateContext(null));
    // defer imgui.ImGui_DestroyContext(imguiCtx);
    // var io = imgui.ImGui_GetIO();
    // const glslVersion = if (builtin.os.tag == .macos) "#version 150" else "#version 130";
    // try checkBool(ImGui_ImplGlfw_InitForOpenGL(window, true));
    // try checkBool(ImGui_ImplOpenGL3_Init(glslVersion));
    // imgui.ImGui_StyleColorsDark(null);

    //
    // todo: delete after program linking


    // const vertices = [_]c.GLfloat{
    //     // positions          // colors           // texture coords
    //      0.5,  0.5, 0.0,   1.0, 0.0, 0.0,   1.0, 1.0, // top right
    //      0.5, -0.5, 0.0,   0.0, 1.0, 0.0,   1.0, 0.0, // bottom right
    //     -0.5, -0.5, 0.0,   0.0, 0.0, 1.0,   0.0, 0.0, // bottom left
    //     -0.5,  0.5, 0.0,   1.0, 1.0, 0.0,   0.0, 1.0,  // top left 
    // };
    // const indices = [_]c.GLuint{
    //     0, 1, 3, // first Triangle
    //     1, 2, 3, // second Triangle
    // };

    // var vao: c.GLuint = 0;
    // c.glGenVertexArrays(1, &vao);
    // c.glBindVertexArray(vao);

    // var vbo: c.GLuint = 0;
    // c.glGenBuffers(1, &vbo);
    // c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    // c.glBufferData(c.GL_ARRAY_BUFFER, vertices.len * @sizeOf(c.GLfloat), &vertices, c.GL_STATIC_DRAW);

    // var ebo: c.GLuint = 0;
    // c.glGenBuffers(1, &ebo);
    // c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, ebo);
    // c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, indices.len * @sizeOf(c.GLuint), &indices, c.GL_STATIC_DRAW);
    
    // // position attribute
    // c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 8 * @sizeOf(c.GLfloat), null);
    // c.glEnableVertexAttribArray(0);
    // // color attribute
    // c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, 8 * @sizeOf(c.GLfloat), @intToPtr(*anyopaque, 3 * @sizeOf(c.GLfloat)));
    // c.glEnableVertexAttribArray(1);
    // // texture coord attribute
    // c.glVertexAttribPointer(2, 2, c.GL_FLOAT, c.GL_FALSE, 8 * @sizeOf(c.GLfloat), @intToPtr(*anyopaque, 6 * @sizeOf(c.GLfloat)));
    // c.glEnableVertexAttribArray(2);


    var resources = try Resources.init();
    defer resources.deinit();

    var engine = try Engine.init(allocator, window);
    defer engine.deinit();

    var game = try Game.init(allocator, &engine, &resources);
    defer allocator.destroy(game);
    defer game.deinit();

    if (args.len >= 2) {
        if (std.mem.eql(u8, args[1], "stress1")) {
            try levels.initStress1(game);
        } else if (std.mem.eql(u8, args[1], "level2")) {
            try levels.initLevel2(game);
        } else if (std.mem.eql(u8, args[1], "level3")) {
            try levels.initLevel3(game, allocator);
        } else {
            try levels.initLevel1(game);
        }
    } else {
        try levels.initLevel1(game);
    }


    // c.glBindBuffer(c.GL_ARRAY_BUFFER, 0); 
    // glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    // c.glBindVertexArray(0);

    // todo: cleanup

    // // load and create texture
    // var x: c_int = 0;
    // var y: c_int = 0;
    // var ch: c_int = 0;
    // const img = stb.stbi_load("res/MiniWorldSprites/Characters/Monsters/Orcs/ArcherGoblin.png", &x, &y, &ch, 0);
    // std.log.debug("x: {} y: {} ch: {} img: {*}", .{ x, y, ch, img });

    // var texture: c.GLuint = 0;
    // c.glGenTextures(1, &texture);
    // c.glBindTexture(c.GL_TEXTURE_2D, texture);
    // c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_REPEAT);
    // c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_REPEAT);
    // c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR_MIPMAP_LINEAR);
    // c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
    // c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA, x, y, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, img);
    // c.glGenerateMipmap(c.GL_TEXTURE_2D);
    // stb.stbi_image_free(img);



    // wireframe
    gl.c.glPolygonMode(gl.c.GL_FRONT_AND_BACK, gl.c.GL_LINE);

    // std.log.debug("DisplaySize: {}", .{io.*.DisplaySize});
    _ = c.glfwSetKeyCallback(window, onKey);
    while (c.glfwWindowShouldClose(window) == 0) {
        const ticks = @intCast(u64,std.time.milliTimestamp());
        c.glfwPollEvents();

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const frameAllocator = arena.allocator();

        try game.update(frameAllocator, ticks);

        // ImGui_ImplOpenGL3_NewFrame();
        // ImGui_ImplGlfw_NewFrame();
        // imgui.ImGui_NewFrame();
        // imgui.ImGui_Render();

        // c.glfwMakeContextCurrent(window);
        // c.glViewport(0, 0, @floatToInt(c_int, io.*.DisplaySize.x), @floatToInt(c_int, io.*.DisplaySize.y));

        // c.glBindTexture(c.GL_TEXTURE_2D, texture);
        // c.glUseProgram(shaderProgram);
        // c.glBindVertexArray(vao);
        // c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
        // c.glBindVertexArray(0);

        // ImGui_ImplOpenGL3_RenderDrawData(imgui.ImGui_GetDrawData());

        try engine.render();
        try game.render();

        c.glfwSwapBuffers(window);
    }
}
