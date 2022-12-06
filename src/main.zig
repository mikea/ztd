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

const sdlZig = @import("sdl.zig");
const sdl = sdlZig.sdl;
const checkNotNull = sdlZig.checkNotNull;
const checkInt = sdlZig.checkInt;
const Sprite = sdlZig.Sprite;
const SpriteSheet = sdlZig.SpriteSheet;

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

    pub fn update(self: *Statistics, ticks: u32, frameAllocator: std.mem.Allocator, game: *Game, updateDurationNs: u64, renderDuration: u64) !void {
        defer self.lastTicks = ticks;
        if (self.lastTicks == 0) {
            return;
        }
        const text = try std.fmt.allocPrintZ(frameAllocator, "{d} fps\n{} monsters\n{d:.0} ms/update\n{e:.0} monsters/sec\n{d:.0} ms/render", .{
            1000 / (ticks - self.lastTicks),
            game.monsters.size(),
            @intToFloat(f64, updateDurationNs) / 1000000,
            @intToFloat(f64, updateDurationNs) / @intToFloat(f64, game.monsters.size()),
            @intToFloat(f64, renderDuration) / 1000000,
        });
        try self.engine.setText(self.textId, text, .{ .x = self.engine.viewport.displaySize.x, .y = 0 }, engine.Alignment.RIGHT, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);
    }
};

pub fn main() !void {
    std.log.info("Starting application, contentDir={s}", .{contentDir});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const leaked = gpa.deinit();
        if (leaked) @panic("Memory Leak Detected");
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    std.debug.print("Arguments: {s}\n", .{args});

    try checkInt(sdl.SDL_Init(sdl.SDL_INIT_VIDEO));
    defer {
        sdl.SDL_Quit();
        std.log.info("application done, exiting", .{});
    }

    var displayMode: sdl.SDL_DisplayMode = undefined;
    try checkInt(sdl.SDL_GetCurrentDisplayMode(0, &displayMode));
    std.debug.print("displayMode: {}\n", .{displayMode});

    const window = try checkNotNull(sdl.SDL_Window, sdl.SDL_CreateWindow("ZTD", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, displayMode.w, displayMode.h, sdl.SDL_WINDOW_SHOWN));
    defer sdl.SDL_DestroyWindow(window);

    try checkInt(sdl.SDL_SetWindowFullscreen(window, sdl.SDL_WINDOW_FULLSCREEN));

    try checkInt(sdl.TTF_Init());
    defer sdl.TTF_Quit();

    //  | sdl.SDL_RENDERER_PRESENTVSYNC
    var renderer = try checkNotNull(sdl.SDL_Renderer, sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED));
    defer sdl.SDL_DestroyRenderer(renderer);

    var resources = try Resources.init();
    defer resources.deinit();

    var eng = try engine.Engine.init(allocator, renderer);
    defer eng.deinit();

    var game = try Game.init(allocator, &eng, &resources);
    defer allocator.destroy(game);
    defer game.deinit();

    if (args.len >= 2) {
        if (std.mem.eql(u8, args[1], "stress1")) {
            try levels.initStress1(game);
        } else {
            try levels.initLevel1(game, allocator);
        }
    } else {
        try levels.initLevel1(game, allocator);
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

        const ticks = sdl.SDL_GetTicks();
        {
            var timer = try std.time.Timer.start();
            defer {
                lastUpdateDuration = timer.read();
            }
            try eng.update(frameAllocator, ticks);
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
        sdl.SDL_RenderPresent(renderer);
    }
}
