const std = @import("std");
const table = @import("table.zig");
const buildOptions = @import("build_options");
const engine = @import("engine.zig");
const Game = @import("game.zig").Game;
const levels = @import("levels.zig");

const model = @import("model.zig");
const Id = model.Id;

const contentDir = buildOptions.content_dir;
const SparseSet = @import("sparse_set.zig").SparseSet;

const sdl = @import("sdl.zig");
const checkNotNull = sdl.checkNotNull;
const checkInt = sdl.checkInt;
const Sprite = sdl.Sprite;
const SpriteSheet = sdl.SpriteSheet;

const Resources = @import("resources.zig").Resources;

const AppError = error{
    NotImplementedError,
    ResourceError,
};

const Statistics = struct {
    engine: *engine.Engine,
    resources: *Resources,

    lastTicks: u32 = 0,
    textId: Id = 0,

    pub fn init(self: *Statistics) !void {
        self.textId = self.engine.ids.nextId();
    }

    pub fn update(self: *Statistics, ticks: u32, frameAllocator: std.mem.Allocator, game: *Game, updateDurationNs: u64, renderDurationNs: u64) !void {
        defer self.lastTicks = ticks;
        if (self.lastTicks == 0) {
            return;
        }
        const text = try std.fmt.allocPrintZ(frameAllocator, "{d} fps\n{d:.0} ms/update\n{d:.0} ms/render\n{e:.1} monsters/sec", .{
            1000 / (ticks - self.lastTicks),
            @intToFloat(f64, updateDurationNs) / 1000000,
            @intToFloat(f64, renderDurationNs) / 1000000,
            @intToFloat(f64, game.monsters.size()) * 1000000000 / @intToFloat(f64, updateDurationNs + renderDurationNs),
        });
        try self.engine.setText(self.textId, text, .{ .x = self.engine.viewport.displaySize.x, .y = 0 }, engine.Alignment.RIGHT, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);
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

    checkInt(sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO));
    defer {
        sdl.c.SDL_Quit();
        std.log.info("application done, exiting", .{});
    }

    var displayMode: sdl.c.SDL_DisplayMode = undefined;
    checkInt(sdl.c.SDL_GetCurrentDisplayMode(0, &displayMode));

    const window = checkNotNull(sdl.c.SDL_Window, sdl.c.SDL_CreateWindow("ZTD", sdl.c.SDL_WINDOWPOS_UNDEFINED, sdl.c.SDL_WINDOWPOS_UNDEFINED, displayMode.w, displayMode.h, sdl.c.SDL_WINDOW_SHOWN));
    defer sdl.c.SDL_DestroyWindow(window);

    checkInt(sdl.c.SDL_SetWindowFullscreen(window, sdl.c.SDL_WINDOW_FULLSCREEN));

    checkInt(sdl.c.TTF_Init());
    defer sdl.c.TTF_Quit();

    var renderer = checkNotNull(sdl.c.SDL_Renderer, sdl.c.SDL_CreateRenderer(window, -1, sdl.c.SDL_RENDERER_ACCELERATED));
    defer sdl.c.SDL_DestroyRenderer(renderer);

    var resources = try Resources.init(renderer);
    defer resources.deinit();

    var eng = try engine.Engine.init(allocator, renderer);
    defer eng.deinit();

    var game = try Game.init(allocator, &eng, &resources);
    defer allocator.destroy(game);
    defer game.deinit();

    if (args.len >= 2) {
        if (std.mem.eql(u8, args[1], "stress1")) {
            try levels.initStress1(game);
        } else if (std.mem.eql(u8, args[1], "level2")) {
            try levels.initLevel2(game, allocator);
        } else {
            try levels.initLevel1(game);
        }
    } else {
        try levels.initLevel1(game);
    }

    var statistics = Statistics{ .engine = &eng, .resources = &resources };
    try statistics.init();

    var lastUpdateDuration: u64 = 0;
    var lastRenderDuration: u64 = 0;

    // main loop
    while (true) {
        while (eng.nextEvent()) |event| {
            try game.event(&event);
        }
        if (!eng.running) {
            break;
        }

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const frameAllocator = arena.allocator();

        const ticks = sdl.c.SDL_GetTicks();
        {
            var timer = try std.time.Timer.start();
            defer {
                lastUpdateDuration = timer.read();
            }
            try game.update(frameAllocator, ticks);
            try statistics.update(ticks, frameAllocator, game, lastUpdateDuration, lastRenderDuration);
        }

        {
            var timer = try std.time.Timer.start();
            defer {
                lastRenderDuration = timer.read();
            }

            try eng.render();
            try game.render();
        }
        sdl.c.SDL_RenderPresent(renderer);
    }
}
