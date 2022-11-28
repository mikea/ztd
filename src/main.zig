const std = @import("std");
const table = @import("table.zig");
const geom = @import("geom.zig");
const buildOptions = @import("build_options");
const engine = @import("engine.zig");
const Game = @import("game.zig").Game;

const Id = engine.Id;

const Vec2 = geom.Vec2;
const Rect = geom.Rect;

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
    fpsId: Id = 0,
    monstersId: Id = 0,
    updateId: Id = 0,
    monsterUpdateId: Id = 0,
    renderId: Id = 0,

    pub fn init(self: *Statistics) !void {
        self.fpsId = self.engine.ids.nextId();
        self.monstersId = self.engine.ids.nextId();
        self.updateId = self.engine.ids.nextId();
        self.monsterUpdateId = self.engine.ids.nextId();
        self.renderId = self.engine.ids.nextId();
    }

    pub fn update(self: *Statistics, ticks: u32, frameAllocator: std.mem.Allocator, game: *Game, updateDurationNs: u64, renderDuration: u64) !void {
        defer self.lastTicks = ticks;

        if (self.lastTicks == 0) {
            return;
        }

        const fps = try std.fmt.allocPrintZ(frameAllocator, "{d} fps", .{1000 / (ticks - self.lastTicks)});
        try self.engine.setText(self.fpsId, fps, .{ .x = 0, .y = 0 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        const monsters = try std.fmt.allocPrintZ(frameAllocator, "{} monsters", .{game.monsters.size()});
        try self.engine.setText(self.monstersId, monsters, .{ .x = 0, .y = 20 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        const updateText = try std.fmt.allocPrintZ(frameAllocator, "{d:.0} ms/update", .{ @intToFloat(f64, updateDurationNs) / 1000000});
        try self.engine.setText(self.updateId, updateText, .{ .x = 0, .y = 40 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        const nsPerMonster = @intToFloat(f64, updateDurationNs) / @intToFloat(f64, game.monsters.size());
        const msMonsterText = try std.fmt.allocPrintZ(frameAllocator, "{e:.0} monsters/sec", .{ 1.0e9 / nsPerMonster});
        try self.engine.setText(self.monsterUpdateId, msMonsterText, .{ .x = 0, .y = 60 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);

        const renderText = try std.fmt.allocPrintZ(frameAllocator, "{d:.0} ms/render", .{ @intToFloat(f64, renderDuration) / 1000000});
        try self.engine.setText(self.renderId, renderText, .{ .x = 0, .y = 80 }, .{ .r = 0, .g = 0, .b = 0, .a = 255 }, self.resources.rubik20);
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

    try checkInt(sdl.SDL_Init(sdl.SDL_INIT_VIDEO));
    defer {
        sdl.SDL_Quit();
        std.log.info("application done, exiting", .{});
    }

    var displayMode: sdl.SDL_DisplayMode = undefined;
    try checkInt(sdl.SDL_GetCurrentDisplayMode(0, &displayMode));

    const window = try checkNotNull(sdl.SDL_Window, sdl.SDL_CreateWindow("ZTD", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, displayMode.w, displayMode.h, sdl.SDL_WINDOW_SHOWN));
    defer sdl.SDL_DestroyWindow(window);

    try checkInt(sdl.SDL_SetWindowFullscreen(window, sdl.SDL_WINDOW_FULLSCREEN));

    try checkInt(sdl.TTF_Init());
    defer sdl.TTF_Quit();

    var renderer = try checkNotNull(sdl.SDL_Renderer, sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED | sdl.SDL_RENDERER_PRESENTVSYNC));
    defer sdl.SDL_DestroyRenderer(renderer);

    var eng = try engine.Engine.init(allocator, renderer);
    defer eng.deinit();

    var game: Game = .{ .engine = &eng };
    try game.init(allocator, renderer);
    defer game.deinit();

    var statistics = Statistics{.engine = &eng, .resources = &game.resources};
    try statistics.init();

    var lastUpdateDuration: u64 = 0;
    var lastRenderDuration: u64 = 0;

    // main loop
    while (true) {
        if (eng.nextEvent()) |event| {
            game.event(&event);
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
        }
        try statistics.update(ticks, frameAllocator, &game, lastUpdateDuration, lastRenderDuration);

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
