const std = @import("std");
const sdl = @import("sdl.zig");
const checkNotNull = sdl.checkNotNull;
const checkInt = sdl.checkInt;

pub const SpriteSheets = enum {
    ARCHER_GOBLIN,
    ORC,
    RED_DEMON,
    WOOD_KEEP,
    WOOD_TOWER,
    WOOD_TOWER2,

    // projectiles
    FIREBALL_PROJECTILE,
    SHORT_ARROW,
    LONG_ARROW,

    // particles
    FLAME_PARTICLE,
};

pub const Resources = struct {
    const sheetSize = @typeInfo(SpriteSheets).Enum.fields.len;

    sheets: [sheetSize]sdl.SpriteSheet,
    rubik20: *sdl.c.TTF_Font,
    rubik8: *sdl.c.TTF_Font,

    pub fn init(renderer: *sdl.Renderer, ) !Resources {
        var sheets: [sheetSize]sdl.SpriteSheet = undefined;
        for (sheets) |_,i| {
            sheets[i] = try loadSheet(renderer, @intToEnum(SpriteSheets, i));
        }
        return .{
            .sheets = sheets,
            .rubik20 = try checkNotNull(sdl.c.TTF_Font, sdl.c.TTF_OpenFont("res/RubikMonoOne-Regular.ttf", 20)),
            .rubik8 = try checkNotNull(sdl.c.TTF_Font, sdl.c.TTF_OpenFont("res/RubikMonoOne-Regular.ttf", 8)),
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.sheets) |*sheet| {
            sheet.deinit();
        }
        sdl.c.TTF_CloseFont(self.rubik20);
        sdl.c.TTF_CloseFont(self.rubik8);
    }

    pub fn getSheet(self: *@This(), sheet: SpriteSheets) *const sdl.SpriteSheet {
        return &self.sheets[@enumToInt(sheet)];
    } 
};

pub fn loadSheet(renderer: *sdl.Renderer, sheet: SpriteSheets) !sdl.SpriteSheet {
    const pi2 = comptime(std.math.pi / 2.0);
    return switch (sheet) {
        SpriteSheets.ARCHER_GOBLIN => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Characters/Monsters/Orcs/ArcherGoblin.png", 16, 16, 0),
        SpriteSheets.ORC => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Characters/Monsters/Orcs/Orc.png", 16, 16, 0),
        SpriteSheets.RED_DEMON => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Characters/Monsters/Demons/RedDemon.png", 16, 16, 0),
        SpriteSheets.WOOD_KEEP => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Buildings/Wood/Keep.png", 32, 32, 0),
        SpriteSheets.WOOD_TOWER => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Buildings/Wood/Tower.png", 16, 16, 0),
        SpriteSheets.WOOD_TOWER2 => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Buildings/Wood/Tower2.png", 16, 16, 0),
        SpriteSheets.FIREBALL_PROJECTILE => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Objects/FireballProjectile.png", 16, 16, -pi2),
        SpriteSheets.SHORT_ARROW => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Objects/ArrowShort.png", 16, 16, -pi2),
        SpriteSheets.LONG_ARROW => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Objects/ArrowLong.png", 16, 16, -pi2),
        SpriteSheets.FLAME_PARTICLE => try sdl.SpriteSheet.load(renderer, "res/particles/flame_06.png", 13, 15, 0),
    };
}
