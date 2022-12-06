const sdlZig = @import("sdl.zig");
const sdl = sdlZig.sdl;
const checkNotNull = sdlZig.checkNotNull;
const checkInt = sdlZig.checkInt;

pub const SpriteSheet = sdlZig.SpriteSheet;
pub const SpriteSheets = enum {
    RED_DEMON,
    WOOD_KEEP,
    WOOD_TOWER,
    FIREBALL_PROJECTILE,
};

pub const Resources = struct {
    redDemon: SpriteSheet,
    tower: SpriteSheet,
    fireballProjectile: SpriteSheet,
    woodKeep: SpriteSheet,
    rubik20: *sdl.TTF_Font,

    pub fn init(renderer: *sdl.SDL_Renderer) !Resources {
        return .{
            .redDemon = try SpriteSheet.load(renderer, "res/MiniWorldSprites/Characters/Monsters/Demons/RedDemon.png", 16, 16),
            .tower = try SpriteSheet.load(renderer, "res/MiniWorldSprites/Buildings/Wood/Tower.png", 16, 16),
            .fireballProjectile = try SpriteSheet.load(renderer, "res/MiniWorldSprites/Objects/FireballProjectile.png", 16, 16),
            .woodKeep = try SpriteSheet.load(renderer, "res/MiniWorldSprites/Buildings/Wood/Keep.png", 32, 32),
            .rubik20 = try checkNotNull(sdl.TTF_Font, sdl.TTF_OpenFont("res/RubikMonoOne-Regular.ttf", 20)),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.redDemon.deinit();
        self.tower.deinit();
        self.fireballProjectile.deinit();
        self.woodKeep.deinit();
        sdl.TTF_CloseFont(self.rubik20);
    }

    pub fn getSheet(self: *const Resources, sheet: SpriteSheets) *const SpriteSheet {
        return switch (sheet) {
            SpriteSheets.RED_DEMON => &self.redDemon,
            SpriteSheets.WOOD_KEEP => &self.woodKeep,
            SpriteSheets.WOOD_TOWER => &self.tower,
            SpriteSheets.FIREBALL_PROJECTILE => &self.fireballProjectile,
        };
    }
};
