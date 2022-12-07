const sdl = @import("sdl.zig");
const checkNotNull = sdl.checkNotNull;
const checkInt = sdl.checkInt;

pub const SpriteSheets = enum {
    ARCHER_GOBLIN,
    ORC,
    RED_DEMON,
    WOOD_KEEP,
    WOOD_TOWER,

    // projectiles
    FIREBALL_PROJECTILE,
    SHORT_ARROW,
};

pub const Resources = struct {
    const sheetSize = @typeInfo(SpriteSheets).Enum.fields.len;

    sheets: [sheetSize]sdl.SpriteSheet,
    rubik20: *sdl.c.TTF_Font,

    pub fn init(renderer: *sdl.Renderer, ) !Resources {
        var sheets: [sheetSize]sdl.SpriteSheet = undefined;
        for (sheets) |_,i| {
            sheets[i] = try loadSheet(renderer, @intToEnum(SpriteSheets, i));
        }
        return .{
            .sheets = sheets,
            .rubik20 = try checkNotNull(sdl.c.TTF_Font, sdl.c.TTF_OpenFont("res/RubikMonoOne-Regular.ttf", 20)),
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.sheets) |*sheet| {
            sheet.deinit();
        }
        sdl.c.TTF_CloseFont(self.rubik20);
    }

    pub fn getSheet(self: *@This(), sheet: SpriteSheets) *const sdl.SpriteSheet {
        return &self.sheets[@enumToInt(sheet)];
    } 
};

pub fn loadSheet(renderer: *sdl.Renderer, sheet: SpriteSheets) !sdl.SpriteSheet {
    return switch (sheet) {
        SpriteSheets.ARCHER_GOBLIN => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Characters/Monsters/Orcs/ArcherGoblin.png", 16, 16),
        SpriteSheets.ORC => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Characters/Monsters/Orcs/Orc.png", 16, 16),
        SpriteSheets.RED_DEMON => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Characters/Monsters/Demons/RedDemon.png", 16, 16),
        SpriteSheets.WOOD_KEEP => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Buildings/Wood/Keep.png", 32, 32),
        SpriteSheets.WOOD_TOWER => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Buildings/Wood/Tower.png", 16, 16),
        SpriteSheets.FIREBALL_PROJECTILE => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Objects/FireballProjectile.png", 16, 16),
        SpriteSheets.SHORT_ARROW => try sdl.SpriteSheet.load(renderer, "res/MiniWorldSprites/Objects/ArrowShort.png", 16, 16),
    };
}
