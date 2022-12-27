const std = @import("std");
const gl = @import("gl.zig");

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

    sheets: [sheetSize]gl.SpriteSheet,
    // rubik20: *sdl.c.TTF_Font,
    // rubik8: *sdl.c.TTF_Font,

    pub fn init() !Resources {
        var sheets: [sheetSize]gl.SpriteSheet = undefined;
        for (sheets) |_,i| {
            sheets[i] = try loadSheet(@intToEnum(SpriteSheets, i));
        }
        return .{
            .sheets = sheets,
            // .rubik20 = checkNotNull(sdl.c.TTF_Font, sdl.c.TTF_OpenFont("res/RubikMonoOne-Regular.ttf", 20)),
            // .rubik8 = checkNotNull(sdl.c.TTF_Font, sdl.c.TTF_OpenFont("res/RubikMonoOne-Regular.ttf", 8)),
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.sheets) |*sheet| {
            sheet.deinit();
        }
        // sdl.c.TTF_CloseFont(self.rubik20);
        // sdl.c.TTF_CloseFont(self.rubik8);
    }

    pub fn getSheet(self: *@This(), sheet: SpriteSheets) *const gl.SpriteSheet {
        return &self.sheets[@enumToInt(sheet)];
    } 
};

pub fn loadSheet(sheet: SpriteSheets) !gl.SpriteSheet {
    const pi2 = comptime(std.math.pi / 2.0);
    return switch (sheet) {
        SpriteSheets.ARCHER_GOBLIN => try gl.SpriteSheet.load("res/MiniWorldSprites/Characters/Monsters/Orcs/ArcherGoblin.png", 16, 16, 0),
        SpriteSheets.ORC => try gl.SpriteSheet.load("res/MiniWorldSprites/Characters/Monsters/Orcs/Orc.png", 16, 16, 0),
        SpriteSheets.RED_DEMON => try gl.SpriteSheet.load("res/MiniWorldSprites/Characters/Monsters/Demons/RedDemon.png", 16, 16, 0),
        SpriteSheets.WOOD_KEEP => try gl.SpriteSheet.load("res/MiniWorldSprites/Buildings/Wood/Keep.png", 32, 32, 0),
        SpriteSheets.WOOD_TOWER => try gl.SpriteSheet.load("res/MiniWorldSprites/Buildings/Wood/Tower.png", 16, 16, 0),
        SpriteSheets.WOOD_TOWER2 => try gl.SpriteSheet.load("res/MiniWorldSprites/Buildings/Wood/Tower2.png", 16, 16, 0),
        SpriteSheets.FIREBALL_PROJECTILE => try gl.SpriteSheet.load("res/MiniWorldSprites/Objects/FireballProjectile.png", 16, 16, -pi2),
        SpriteSheets.SHORT_ARROW => try gl.SpriteSheet.load("res/MiniWorldSprites/Objects/ArrowShort.png", 16, 16, -pi2),
        SpriteSheets.LONG_ARROW => try gl.SpriteSheet.load("res/MiniWorldSprites/Objects/ArrowLong.png", 16, 16, -pi2),
        SpriteSheets.FLAME_PARTICLE => try gl.SpriteSheet.load("res/particles/flame_06.png", 13, 15, 0),
    };
}

