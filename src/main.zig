const std = @import("std");
const builtin = @import("builtin");
const gl = @import("gl.zig");
const c = gl.c;
const Resources = @import("resources.zig").Resources;
const Engine = @import("engine.zig").Engine;
const Game = @import("game.zig").Game;
const levels = @import("levels.zig");
const imgui = @import("imgui.zig");
const utils = @import("utils.zig");
const ui = @import("ui.zig");

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

    var game = try Game.init(allocator, &engine, &resources);
    defer allocator.destroy(game);
    defer game.deinit();

    if (args.len >= 2) {
        if (std.mem.eql(u8, args[1], "stress1")) {
            try levels.initStress1(game);
        } else if (std.mem.eql(u8, args[1], "stress2")) {
            try levels.initStress2(game);
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

    var stats = ui.Statistics{};

    var wireframe: bool = false;
    var showDemo: bool = false;

    while (c.glfwWindowShouldClose(window) == 0) {
        const ticks = @intCast(u64, std.time.milliTimestamp());
        for (gl.pollEvents()) |event| {
            if (!imguiImpl.wantCapture(&event)) {
                engine.onEvent(&event);
                try game.onEvent(&event);                
            }
        }

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const frameAllocator = arena.allocator();

        gl.c.glPolygonMode(gl.c.GL_FRONT_AND_BACK, if (wireframe) gl.c.GL_LINE else gl.c.GL_FILL);

        var updateDuration: u64 = 0;
        {
            var timer = try std.time.Timer.start();
            defer {
                updateDuration = timer.read();
            }
            try game.update(frameAllocator, ticks);
            try engine.update(ticks);
        }

        imguiImpl.newFrame();

        var renderDuration: u64 = 0;
        {
            var timer = try std.time.Timer.start();
            defer {
                renderDuration = timer.read();
            }
            try engine.render();
            try game.render(frameAllocator);
        }

        try stats.render(ticks, frameAllocator, game, updateDuration, renderDuration);

        // todo: move out
        const viewport = imgui.c.ImGui_GetMainViewport();
        imgui.c.ImGui_SetNextWindowPosEx(.{ .x = 0, .y = viewport.*.Size.y}, imgui.c.ImGuiCond_Appearing, .{.x = 0, .y = 1});
        if (imgui.c.ImGui_Begin("Debug", null, 0)) {
            _ = imgui.c.ImGui_Checkbox("Wireframe", &wireframe);
            _ = imgui.c.ImGui_Checkbox("Show ImGui Demo", &showDemo);
            if (showDemo) {
                imgui.c.ImGui_ShowDemoWindow(null);
            }
        }
        imgui.c.ImGui_End();

        imguiImpl.render();
        c.glfwSwapBuffers(window);
    }
}
