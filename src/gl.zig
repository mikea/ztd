const std = @import("std");
const builtin = @import("builtin");

const utils = @import("utils.zig");
const geom = @import("geom.zig");
const Vec = geom.Vec;
const Rect = geom.Rect;

pub const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
});

const Error = error{ GenericError, NullPointer };

pub const Event = union(enum) {
    keyPress: struct {
        key: c_int,
    },
    mouseWheel: struct {
        dx: f64,
        dy: f64,
    },
    mouseButton: struct {
        action: enum { press },
        button: enum { left, right },
    },
    mouseMove: struct {
        pos: Vec,
    },
};

var events: std.ArrayList(Event) = undefined;

pub fn framebufferSize(window: *c.GLFWwindow) Vec {
    var w: c.GLint = 0;
    var h: c.GLint = 0;
    c.glfwGetFramebufferSize(window, &w, &h);
    return Vec.initInt(w, h);
}

pub fn init(allocator: std.mem.Allocator) !*c.GLFWwindow {
    events = std.ArrayList(Event).init(allocator);

    _ = c.glfwSetErrorCallback(onError);
    try checkCBool(c.glfwInit());

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

    c.glfwMakeContextCurrent(window);
    _ = c.glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);

    try checkCBool(c.gladLoadGLLoader(@ptrCast(c.GLADloadproc, &c.glfwGetProcAddress)));

    _ = c.glfwSetKeyCallback(window, onKey);
    _ = c.glfwSetScrollCallback(window, onScroll);
    _ = c.glfwSetMouseButtonCallback(window, onMouseButton);
    _ = c.glfwSetCursorPosCallback(window, onCursorPos);

    return window;
}

pub fn deinit(window: *c.GLFWwindow) void {
    c.glfwDestroyWindow(window);
    c.glfwTerminate();
    events.deinit();
}

pub fn pollEvents() []Event {
    events.clearRetainingCapacity();
    c.glfwPollEvents();
    return events.items;
}

fn onError(err: c_int, desc: ?[*:0]const u8) callconv(.C) void {
    std.log.err("glfw error {}: {any}\n", .{ err, desc });
}

fn framebufferSizeCallback(_: ?*c.GLFWwindow, width: c.GLint, height: c.GLint) callconv(.C) void {
    c.glViewport(0, 0, width, height);
}

fn checkCBool(i: c_int) !void {
    if (i == 0) {
        return Error.GenericError;
    }
}

fn checkBool(b: bool) !void {
    if (!b) {
        return Error.GenericError;
    }
}

fn checkNotNull(ptr: anytype) !utils.Required(@TypeOf(ptr)) {
    return ptr orelse Error.NullPointer;
}

fn onKey(_: ?*c.GLFWwindow, key: c_int, _: c_int, action: c_int, _: c_int) callconv(.C) void {
    if (action == c.GLFW_PRESS) {
        events.append(.{ .keyPress = .{ .key = key } }) catch @panic("can't add events");
    }
}

fn onScroll(_: ?*c.GLFWwindow, dx: f64, dy: f64) callconv(.C) void {
    events.append(.{ .mouseWheel = .{ .dx = dx, .dy = dy } }) catch @panic("can't add events");
}

fn onMouseButton(_: ?*c.GLFWwindow, button: c_int, action: c_int, _: c_int) callconv(.C) void {
    if (action == c.GLFW_PRESS) {
        events.append(.{ .mouseButton = .{
            .button = switch (button) {
                c.GLFW_MOUSE_BUTTON_RIGHT => .right,
                else => .left,
            },
            .action = .press,
        } }) catch @panic("can't add events");
    }
}

fn onCursorPos(_: ?*c.GLFWwindow, x: f64, y: f64) callconv(.C) void {
    events.append(.{ .mouseMove = .{ .pos = Vec.init(@floatCast(f32, x), @floatCast(f32, y)) } }) catch @panic("can't add events");
}

pub fn getCursorPos(window: *c.GLFWwindow) Vec {
    var xpos: f64 = undefined;
    var ypos: f64 = undefined;
    c.glfwGetCursorPos(window, &xpos, &ypos);
    return Vec.init(@floatCast(f32, xpos), @floatCast(f32, ypos));
}

pub fn genBuffer() c.GLuint {
    var buffer: c.GLuint = 0;
    c.glGenBuffers(1, &buffer);
    return buffer;
}
