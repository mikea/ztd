const std = @import("std");
const gl = @import("gl.zig");
const sprites = @import("sprites.zig");
const truetype = @import("truetype.zig");

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

    sheets: [sheetSize]sprites.SpriteSheet,
    rubik: truetype.FontInfo,

    pub fn init() !Resources {
        var sheets: [sheetSize]sprites.SpriteSheet = undefined;
        for (sheets) |_,i| {
            sheets[i] = try loadSheet(@intToEnum(SpriteSheets, i));
        }
        return .{
            .sheets = sheets,
            .rubik = try truetype.FontInfo.init(@embedFile("res/RubikMonoOne-Regular.ttf")),
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.sheets) |*sheet| {
            sheet.deinit();
        }
    }

    pub fn getSheet(self: *@This(), sheet: SpriteSheets) *const sprites.SpriteSheet {
        return &self.sheets[@enumToInt(sheet)];
    } 
};

const pi2 = (std.math.pi / 2.0);

pub fn loadSheet(sheet: SpriteSheets) !sprites.SpriteSheet {
    return switch (sheet) {
        SpriteSheets.ARCHER_GOBLIN => try sprites.SpriteSheet.load("res/MiniWorldSprites/Characters/Monsters/Orcs/ArcherGoblin.png", 16, 16, 0),
        SpriteSheets.ORC => try sprites.SpriteSheet.load("res/MiniWorldSprites/Characters/Monsters/Orcs/Orc.png", 16, 16, 0),
        SpriteSheets.RED_DEMON => try sprites.SpriteSheet.load("res/MiniWorldSprites/Characters/Monsters/Demons/RedDemon.png", 16, 16, 0),
        SpriteSheets.WOOD_KEEP => try sprites.SpriteSheet.load("res/MiniWorldSprites/Buildings/Wood/Keep.png", 32, 32, 0),
        SpriteSheets.WOOD_TOWER => try sprites.SpriteSheet.load("res/MiniWorldSprites/Buildings/Wood/Tower.png", 16, 16, 0),
        SpriteSheets.WOOD_TOWER2 => try sprites.SpriteSheet.load("res/MiniWorldSprites/Buildings/Wood/Tower2.png", 16, 16, 0),
        SpriteSheets.FIREBALL_PROJECTILE => try sprites.SpriteSheet.load("res/MiniWorldSprites/Objects/FireballProjectile.png", 16, 16, pi2),
        SpriteSheets.SHORT_ARROW => try sprites.SpriteSheet.load("res/MiniWorldSprites/Objects/ArrowShort.png", 16, 16, pi2),
        SpriteSheets.LONG_ARROW => try sprites.SpriteSheet.load("res/MiniWorldSprites/Objects/ArrowLong.png", 16, 16, pi2),
        SpriteSheets.FLAME_PARTICLE => try sprites.SpriteSheet.load("res/particles/flame_06.png", 13, 15, 0),
    };
}

