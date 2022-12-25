const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
});

const imgui = @cImport({
    @cInclude("stdlib.h");
    @cInclude("stdarg.h");
    @cInclude("cimgui/cimgui.h");
});

const GlfwError = error{ GenericError, NullPointer };

pub fn checkCBool(i: c_int) !void {
    if (i == 0) {
        return GlfwError.GenericError;
    }
}

pub fn checkBool(b: bool) !void {
    if (!b) {
        return GlfwError.GenericError;
    }
}

fn onError(err: c_int, desc: ?[*:0]const u8) callconv(.C) void {
    std.log.err("glfw error {}: {any}\n", .{ err, desc });
}

fn Required(comptime t: type) type {
    const info = @typeInfo(t);
    return switch (info) {
        .Optional => |o| o.child,
        else => @compileError("Optional type expected"),
    };
}
fn checkNotNull(ptr: anytype) !Required(@TypeOf(ptr)) {
    return ptr orelse GlfwError.NullPointer;
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
    _ = c.glfwSetErrorCallback(onError);
    try checkCBool(c.glfwInit());
    defer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 2);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 0);

    const monitor = try checkNotNull(c.glfwGetPrimaryMonitor());
    const mode = c.glfwGetVideoMode(monitor);

    c.glfwWindowHint(c.GLFW_RED_BITS, mode.*.redBits);
    c.glfwWindowHint(c.GLFW_GREEN_BITS, mode.*.greenBits);
    c.glfwWindowHint(c.GLFW_BLUE_BITS, mode.*.blueBits);
    c.glfwWindowHint(c.GLFW_REFRESH_RATE, mode.*.refreshRate);

    const window = try checkNotNull(c.glfwCreateWindow(mode.*.width, mode.*.height, "My Window", monitor, null));
    defer c.glfwDestroyWindow(window);

    c.glfwMakeContextCurrent(window);
    try checkCBool(c.gladLoadGL());

    const imguiCtx = try checkNotNull(imgui.ImGui_CreateContext(null));
    defer imgui.ImGui_DestroyContext(imguiCtx);
    var io = imgui.ImGui_GetIO();

    const glslVersion = if (builtin.os.tag == .macos) "#version 150" else "#version 130";

    try checkBool(ImGui_ImplGlfw_InitForOpenGL(window, true));
    try checkBool(ImGui_ImplOpenGL3_Init(glslVersion));

    imgui.ImGui_StyleColorsDark(null);

    var showDemoWindow: bool = true;

    _ = c.glfwSetKeyCallback(window, onKey);
    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();

        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        imgui.ImGui_NewFrame();

        if (showDemoWindow) {
            imgui.ImGui_ShowDemoWindow(&showDemoWindow);
        }

        imgui.ImGui_Render();
        c.glfwMakeContextCurrent(window);
        c.glViewport(0, 0, @floatToInt(c_int, io.*.DisplaySize.x), @floatToInt(c_int, io.*.DisplaySize.y));
        c.glClearColor(0.45, 0.55, 0.60, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        ImGui_ImplOpenGL3_RenderDrawData(imgui.ImGui_GetDrawData());

        c.glfwSwapBuffers(window);
    }
}
