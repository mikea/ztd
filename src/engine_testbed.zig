const std = @import("std");
const builtin = @import("builtin");
const gl = @import("gl.zig");
const c = gl.c;
const Resources = @import("resources.zig").Resources;
const Engine = @import("engine.zig").Engine;
const levels = @import("levels.zig");
const imgui = @import("imgui.zig");
const utils = @import("utils.zig");
const data = @import("data.zig");

const geom = @import("geom.zig");
const Vec = geom.Vec;
const Rect = geom.Rect;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const leaked = gpa.deinit();
        if (leaked) @panic("Memory Leak Detected");
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const window = try gl.init(allocator);
    defer gl.deinit(window);

    var imguiImpl = try imgui.init(window);
    defer imguiImpl.deinit();

    var resources = try Resources.init(allocator);
    defer resources.deinit(allocator);

    var engine = try Engine.init(allocator, window, &resources.atlas);
    defer engine.deinit();

    var wireframe: bool = false;

    {
        const d = data.Orc;
        const sheet = resources.getSheet(d.sheet);
        try engine.addAnimation(engine.ids.nextId(), Rect.initCentered(Vec.init(0, 0), d.size), sheet, &d.animations.walk, .MONSTER);
        try engine.addAnimation(engine.ids.nextId(), Rect.initCentered(Vec.init(0, sheet.desc.spriteHeight * 2), d.size), sheet, &d.animations.attack, .MONSTER);
    }

    while (c.glfwWindowShouldClose(window) == 0) {
        const ticks = @intCast(u64, std.time.milliTimestamp());
        for (gl.pollEvents()) |event| {
            engine.onEvent(&event);

            if (event == .keyPress) {
                if (event.keyPress.key == gl.c.GLFW_KEY_Q) {
                    std.c.exit(0);
                } 
            }
        }

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        // const frameAllocator = arena.allocator();

        gl.c.glPolygonMode(gl.c.GL_FRONT_AND_BACK, if (wireframe) gl.c.GL_LINE else gl.c.GL_FILL);

        try engine.update(ticks);

        imguiImpl.newFrame();
        try engine.render();

        const viewport = imgui.c.ImGui_GetMainViewport();
        imgui.c.ImGui_SetNextWindowPosEx(.{ .x = 0, .y = viewport.*.Size.y }, imgui.c.ImGuiCond_Appearing, .{ .x = 0, .y = 1 });
        if (imgui.c.ImGui_Begin("Debug", null, 0)) {
            _ = imgui.c.ImGui_Checkbox("Wireframe", &wireframe);
        }
        imgui.c.ImGui_End();

        imguiImpl.render();
        c.glfwSwapBuffers(window);
    }
}
