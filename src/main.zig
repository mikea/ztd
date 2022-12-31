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

const Statistics = struct {
    lastTicks: u64 = 0,

    pub fn render(self: *Statistics, ticks: u64, frameAllocator: std.mem.Allocator, game: *Game, updateDurationNs: u64, renderDurationNs: u64) !void {
        defer self.lastTicks = ticks;
        if (self.lastTicks == 0 or ticks == self.lastTicks) {
            return;
        }
        const text = try std.fmt.allocPrintZ(frameAllocator, "{d} fps\n{d:.0} ms/update\n{d:.0} ms/render\n{d} sprites\n{e:.1} monsters/sec", .{
            1000 / (ticks - self.lastTicks),
            @intToFloat(f64, updateDurationNs) / 1000000,
            @intToFloat(f64, renderDurationNs) / 1000000,
            game.engine.renderedSprites,
            @intToFloat(f64, game.monsters.size()) * 1000000000 / @intToFloat(f64, updateDurationNs + renderDurationNs),
        });

        const viewport = imgui.c.ImGui_GetMainViewport();
        imgui.c.ImGui_SetNextWindowPosEx(.{ .x = viewport.*.Size.x, .y = viewport.*.Size.y}, imgui.c.ImGuiCond_Appearing, .{.x = 1, .y = 1});
        if (imgui.c.ImGui_Begin("Statistics", null, 0)) {
            imgui.c.ImGui_Text(text);
        }
        imgui.c.ImGui_End();
    }
};

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

    var ui = try imgui.init(window);
    defer ui.deinit();

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

    var stats = Statistics{};

    var wireframe: bool = false;

    while (c.glfwWindowShouldClose(window) == 0) {
        const ticks = @intCast(u64, std.time.milliTimestamp());
        for (gl.pollEvents()) |event| {
            engine.onEvent(&event);
            try game.onEvent(&event);
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
        }

        ui.newFrame();

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

        if (imgui.c.ImGui_Begin("Debug", null, 0)) {
            _ = imgui.c.ImGui_Checkbox("Wireframe", &wireframe);
        }
        imgui.c.ImGui_End();

        ui.render();

        c.glfwSwapBuffers(window);
    }
}
