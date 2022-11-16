const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const buildOptions = @import("build_options");
const contentDir = buildOptions.content_dir;

const AppError = error{
    SdlInitError,
    NotImplementedError,
    SdlError,
    ResourceError,
};

fn checkInt(i: c_int) !void {
    if (i < 0) {
        return AppError.SdlInitError;
    }
}

fn checkNotNull(comptime T: type, ptr: ?*T) !*T {
    return ptr orelse AppError.SdlInitError;
}

const Vec2 = struct {
    x: f32,
    y: f32,

    fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    fn minus(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    fn direction(from: Vec2, to: Vec2) Vec2 {
        return minus(to, from).normalized();
    }

    fn mul(self: *const Vec2, a: f32) Vec2 {
        return .{ .x = self.x * a, .y = self.y * a };
    }

    fn norm(self: *const Vec2) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    fn normalized(self: *const Vec2) Vec2 {
        const n = self.norm();
        return .{ .x = self.x / n, .y = self.y / n };
    }

    pub fn format(
        self: Vec2,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("({},{})", .{
            self.x,
            self.y,
        });
    }
};

const FieldObject = struct {
    pos: Vec2,
};

const Rect = struct {
    a: Vec2,
    b: Vec2,

    fn centered(c: Vec2, aSize: Vec2) Rect {
        const s2 = aSize.mul(1.0 / 2.0);
        return .{ .a = c.minus(s2), .b = c.add(s2) };
    }

    fn sized(o: Vec2, aSize: Vec2) Rect {
        return .{ .a = o, .b = o.add(aSize) };
    }

    fn intersects(self: *const Rect, other: Rect) bool {
        // ((X,Y),(A,B)) and ((X1,Y1),(A1,B1))
        // (X,Y) = (self.a.x, self.a.y)
        // (A,B) = (self.b.x, self.b.y)
        // (X1,Y1) = (other.a.x, other.a.y)
        // (A1,B1) = (other.b.x, other.b.y)
        // A<X1 or A1<X or B<Y1 or B1<Y
        if ((self.b.x < other.a.x) or (other.b.x < self.a.x) or (self.b.y < other.a.y) or (other.b.y < self.a.y)) {
            return false;
        }
        return true;
    }

    fn size(self: *const Rect) Vec2 {
        return self.b.minus(self.a);
    }

    fn center(self: *const Rect) Vec2 {
        return self.a.add(self.size().mul(1.0 / 2.0));
    }

    pub fn format(
        self: Rect,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("[{},{}]", .{
            self.a,
            self.b,
        });
    }
};

fn Table(comptime T: type) type {
    return struct {
        const List = std.ArrayList(T);

        pub const Iterator = struct {
            l: *List,
            i: u64,

            fn next(self: *@This()) ?*T {
                if (self.i >= self.l.*.items.len) {
                    return null;
                }
                const result = &self.l.*.items[self.i];
                self.i += 1;
                return result;
            }
        };

        list: List = undefined,

        fn init(allocator: std.mem.Allocator) @This() {
            return .{ .list = List.init(allocator) };
        }

        fn deinit(self: *@This()) void {
            self.list.deinit();
        }

        fn add(self: *@This(), t: T) !void {
            try self.list.append(t);
        }

        pub fn iterator(self: *@This()) Iterator {
            return .{ .l = &self.list, .i = 0 };
        }
    };
}

const Game = struct {
    const FieldObjects = Table(FieldObject);

    displaySize: Vec2,

    lastTicks: u32 = 0,

    view: Rect = undefined,
    objects: FieldObjects = undefined,

    fn init(self: *Game, allocator: std.mem.Allocator) !void {
        self.objects = FieldObjects.init(allocator);

        // initially 1000 wide, centered on origin
        const w = 1000;
        const h = w * self.displaySize.y / self.displaySize.x;
        self.view = .{ .a = .{ .x = -w / 2, .y = -h / 2 }, .b = .{ .x = w / 2, .y = h / 2 } };

        const grid = 100;
        const step = 20;

        var i: i32 = -grid + 1;
        while (i < grid) : (i += 1) {
            var j: i32 = -grid + 1;
            while (j < grid) : (j += 1) {
                try self.objects.add(.{ .pos = .{ .x = @intToFloat(f32, i) * step, .y = @intToFloat(f32, j) * step } });
            }
        }
    }

    fn deinit(self: *Game) void {
        self.objects.deinit();
    }

    fn update(self: *Game, ticks: u32) void {
        if (self.lastTicks == 0) {
            self.lastTicks = ticks;
            return;
        }

        // const t = 0.001 * @intToFloat(f32, frameTicks - startTicks);
        const dt = 0.001 * @intToFloat(f32, ticks - self.lastTicks);

        {
            const c: Vec2 = .{ .x = 0, .y = 0 };

            // update state
            var it = self.objects.iterator();
            while (it.next()) |o| {
                const d = Vec2.minus(c, o.pos);
                const n = d.norm();
                if (n > 1.0e-2) {
                    const dn = d.mul(100 * dt / n);
                    o.pos = o.pos.add(dn);
                }
            }
        }

        self.lastTicks = ticks;
    }

    fn render(self: *Game, renderer: *sdl.SDL_Renderer) !void {
        var sdlViewport: sdl.SDL_Rect = undefined;
        sdl.SDL_RenderGetViewport(renderer, &sdlViewport);

        const viewport = Rect.sized(.{ .x = @intToFloat(f32, sdlViewport.x), .y = @intToFloat(f32, sdlViewport.y) }, .{ .x = @intToFloat(f32, sdlViewport.w), .y = @intToFloat(f32, sdlViewport.h) });
        const view = self.view;

        // std.log.info("viewport: {}", .{viewport});
        // std.log.info("view: {}", .{view});

        const translation = viewport.a.minus(view.a);
        const scale = viewport.size().x / view.size().x;
        // std.log.info("translation: {} scale: {}", .{ translation, scale });

        try checkInt(sdl.SDL_SetRenderDrawColor(renderer, 0xff, 0, 0, 0xff));

        // draw objects
        var it = self.objects.iterator();
        while (it.next()) |o| {
            const rect = Rect.centered(.{ .x = o.pos.x, .y = -o.pos.y }, .{ .x = 2, .y = 2 });
            if (self.view.intersects(rect)) {
                const newA = rect.a.add(translation).mul(scale);
                const newSize = rect.size().mul(scale);

                // std.log.info("pos: {} rect: {} newA: {} newSize: {}", .{ o.pos, rect, newA, newSize });

                const sdlRect = sdl.SDL_Rect{
                    .x = @floatToInt(i32, newA.x),
                    .y = @floatToInt(i32, newA.y),
                    .w = @floatToInt(i32, newSize.x),
                    .h = @floatToInt(i32, newSize.y),
                };
                try checkInt(sdl.SDL_RenderFillRect(renderer, &sdlRect));
            }
        }
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

    const window = sdl.SDL_CreateWindow("ZTD", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, displayMode.w, displayMode.h, sdl.SDL_WINDOW_SHOWN);
    if (window == null) {
        return AppError.SdlInitError;
    }
    defer sdl.SDL_DestroyWindow(window);
    try checkInt(sdl.SDL_SetWindowFullscreen(window, sdl.SDL_WINDOW_FULLSCREEN));

    try checkInt(sdl.TTF_Init());
    defer sdl.TTF_Quit();

    const font = sdl.TTF_OpenFont("res/RubikMonoOne-Regular.ttf", 28);
    if (font == null) {
        return AppError.ResourceError;
    }
    defer sdl.TTF_CloseFont(font);

    var renderer = try checkNotNull(sdl.SDL_Renderer, sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED | sdl.SDL_RENDERER_PRESENTVSYNC));
    defer sdl.SDL_DestroyRenderer(renderer);

    var game: Game = .{
        .displaySize = .{ .x = @intToFloat(f32, displayMode.w), .y = @intToFloat(f32, displayMode.h) },
    };
    try game.init(allocator);
    defer game.deinit();

    // main loop

    const startTicks = sdl.SDL_GetTicks();
    var lastFrameTicks = startTicks;

    mainloop: while (true) {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const frameAllocator = arena.allocator();

        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => break :mainloop,
                sdl.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    sdl.SDLK_ESCAPE => break :mainloop,
                    sdl.SDLK_UP => std.log.debug("up", .{}),
                    sdl.SDLK_DOWN => std.log.debug("down", .{}),
                    sdl.SDLK_LEFT => std.log.debug("left", .{}),
                    sdl.SDLK_RIGHT => std.log.debug("right", .{}),
                    else => {},
                },
                else => {},
            }
        }
        const frameTicks = sdl.SDL_GetTicks();
        game.update(frameTicks);

        try checkInt(sdl.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff));
        try checkInt(sdl.SDL_RenderClear(renderer));

        try game.render(renderer);

        // draw fps
        if (frameTicks > lastFrameTicks) {
            var text = try std.fmt.allocPrintZ(frameAllocator, "FPS: {}", .{1000 / (frameTicks - lastFrameTicks)});
            const tt: [*:0]const u8 = text;
            const textSurface = sdl.TTF_RenderText_Solid(font, tt, .{ .r = 0, .g = 0, .b = 255, .a = 255 });
            defer sdl.SDL_FreeSurface(textSurface);

            const texture = try checkNotNull(sdl.SDL_Texture, sdl.SDL_CreateTextureFromSurface(renderer, textSurface));
            defer sdl.SDL_DestroyTexture(texture);

            const srcRect: sdl.SDL_Rect = .{
                .x = 0,
                .y = 0,
                .w = textSurface.*.w,
                .h = textSurface.*.h,
            };
            const dstRect: sdl.SDL_Rect = .{
                .x = 0,
                .y = 0,
                .w = textSurface.*.w,
                .h = textSurface.*.h,
            };

            try checkInt(sdl.SDL_RenderCopy(renderer, texture, &srcRect, &dstRect));
        }

        sdl.SDL_RenderPresent(renderer);

        lastFrameTicks = frameTicks;
    }
}
