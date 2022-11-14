const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const SCREEN_WIDTH = 640;
const SCREEN_HEIGHT = 480;

const AppError = error{
    SdlInitError,
    NotImplementedError,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const leaked = gpa.deinit();
        if (leaked) @panic("Memory Leak Detected");
    }


    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) < 0) {
        return AppError.SdlInitError;
    }
    defer {
        sdl.SDL_Quit();
        std.log.info("application done, exiting", .{});
    }

    const window = sdl.SDL_CreateWindow("ZTD", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, SCREEN_WIDTH, SCREEN_HEIGHT, sdl.SDL_WINDOW_SHOWN);
    if (window == null) {
        return AppError.SdlInitError;
    }
    defer sdl.SDL_DestroyWindow(window);

    const font = sdl.TTF_OpenFont("res/RubikMonoOne-Regular.ttf", 28);
    if (font == null) {
        return AppError.SdlInitError;
    }

    var renderer = sdl.SDL_CreateRenderer(window, 0, sdl.SDL_RENDERER_PRESENTVSYNC);
    defer sdl.SDL_DestroyRenderer(renderer);

    // const surface = sdl.SDL_GetWindowSurface(window);
    // _ = sdl.SDL_FillRect(surface, null, sdl.SDL_MapRGB(surface.*.format, 0xff, 0xff, 0xff));
    // _ = sdl.SDL_UpdateWindowSurface(window);

    const startTicks = sdl.SDL_GetTicks();
    mainloop: while (true) {
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
        const t = 0.001 * @intToFloat(f32, sdl.SDL_GetTicks() - startTicks);


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

        var text = try std.fmt.allocPrintZ(allocator, "Current time: {}", .{t});
        const tt: [*:0]const u8 = text;
        const textSurface = sdl.TTF_RenderText_Solid(font, tt, .{.r = 0, .g = 0, .b = 255, .a = 255});
        _ = textSurface;

        sdl.SDL_RenderPresent(renderer);
    }
}
