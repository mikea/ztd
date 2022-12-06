const sdlZig = @import("sdl.zig");
const sdl = sdlZig.sdl;
const checkNotNull = sdlZig.checkNotNull;
const checkInt = sdlZig.checkInt;

pub const SpriteSheet = sdlZig.SpriteSheet;
pub const SpriteSheets = enum {
    ORC,
    RED_DEMON,
    WOOD_KEEP,
    WOOD_TOWER,
    FIREBALL_PROJECTILE,
};

pub const Resources = struct {
    const sheetSize = @typeInfo(SpriteSheets).Enum.fields.len;

    sheets: [sheetSize]?SpriteSheet = [_]?SpriteSheet{null} ** sheetSize,
    rubik20: *sdl.TTF_Font,

    pub fn init() !Resources {
        return .{
            .rubik20 = try checkNotNull(sdl.TTF_Font, sdl.TTF_OpenFont("res/RubikMonoOne-Regular.ttf", 20)),
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.sheets) |maybeSheet| {
            if (maybeSheet) |sheet| {
                sheet.deinit();
            }
        }
        sdl.TTF_CloseFont(self.rubik20);
    }

    pub fn getSheet(self: *@This(), renderer: *sdl.SDL_Renderer, sheet: SpriteSheets) !*const SpriteSheet {
        const i = @enumToInt(sheet);
        if (self.sheets[i]) |*s| {
            return s;
        }
        self.sheets[i] = try loadSheet(renderer, sheet);
        return &(self.sheets[i].?);
    } 
};

pub fn loadSheet(renderer: *sdl.SDL_Renderer, sheet: SpriteSheets) !SpriteSheet {
    return switch (sheet) {
        SpriteSheets.ORC => try SpriteSheet.load(renderer, "res/MiniWorldSprites/Characters/Monsters/Orcs/Orc.png", 16, 16),
        SpriteSheets.RED_DEMON => try SpriteSheet.load(renderer, "res/MiniWorldSprites/Characters/Monsters/Demons/RedDemon.png", 16, 16),
        SpriteSheets.WOOD_KEEP => try SpriteSheet.load(renderer, "res/MiniWorldSprites/Buildings/Wood/Keep.png", 32, 32),
        SpriteSheets.WOOD_TOWER => try SpriteSheet.load(renderer, "res/MiniWorldSprites/Buildings/Wood/Tower.png", 16, 16),
        SpriteSheets.FIREBALL_PROJECTILE => try SpriteSheet.load(renderer, "res/MiniWorldSprites/Objects/FireballProjectile.png", 16, 16),
    };
}
