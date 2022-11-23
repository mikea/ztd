pub const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL2/SDL_ttf.h");
});

const SdlError = error{
    SdlError,
};

pub fn checkInt(i: c_int) !void {
    if (i < 0) {
        return SdlError.SdlError;
    }
}

pub fn checkNotNull(comptime T: type, ptr: ?*T) !*T {
    return ptr orelse SdlError.SdlError;
}
