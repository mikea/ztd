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

    var renderer = sdl.SDL_CreateRenderer(window, 0, sdl.SDL_RENDERER_PRESENTVSYNC);
    defer sdl.SDL_DestroyRenderer(renderer);

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
        const t = 0.001 * @intToFloat(f32, frameTicks - startTicks);


        _ = sdl.SDL_SetRenderDrawColor(renderer, 0xff, 0xff, 0xff, 0xff);
        _ = sdl.SDL_RenderClear(renderer);

        const r = 100 * @cos(t * 5);
        const x = 2 * std.math.pi / 3.0;
        var rect = sdl.SDL_Rect{ .x = 0, .y = 0, .w = 60, .h = 60 };
        rect.x = 290 + @floatToInt(i32, r * @cos(t));
        rect.y = 170 + @floatToInt(i32, r * @sin(t));
        _ = sdl.SDL_SetRenderDrawColor(renderer, 0xff, 0, 0, 0xff);
        _ = sdl.SDL_RenderFillRect(renderer, &rect);
        rect.x = 290 + @floatToInt(i32, r * @cos(t + x));
        rect.y = 170 + @floatToInt(i32, r * @sin(t + x));
        _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 0xff, 0, 0xff);
        _ = sdl.SDL_RenderFillRect(renderer, &rect);
        rect.x = 290 + @floatToInt(i32, r * @cos(t + 2 * x));
        rect.y = 170 + @floatToInt(i32, r * @sin(t + 2 * x));
        _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 0xff, 0xff);
        _ = sdl.SDL_RenderFillRect(renderer, &rect);

        var text = try std.fmt.allocPrintZ(frameAllocator, "FPS: {}", .{1000 / (frameTicks - lastFrameTicks)});
        const tt: [*:0]const u8 = text;
        const textSurface = sdl.TTF_RenderText_Solid(font, tt, .{.r = 0, .g = 0, .b = 255, .a = 255});
        defer sdl.SDL_FreeSurface(textSurface);

        const texture = try checkNotNull(sdl.SDL_Texture, sdl.SDL_CreateTextureFromSurface(renderer, textSurface));
        defer sdl.SDL_DestroyTexture(texture);

        const srcRect: sdl.SDL_Rect = .{
            .x = 0, .y = 0, .w = textSurface.*.w, .h = textSurface.*.h,
        };
        const dstRect: sdl.SDL_Rect = .{
            .x = 0, .y = 0, .w = textSurface.*.w, .h = textSurface.*.h,
        };

        try checkInt(sdl.SDL_RenderCopy(renderer, texture, &srcRect, &dstRect));

        sdl.SDL_RenderPresent(renderer);

        lastFrameTicks = frameTicks;
    }
}
