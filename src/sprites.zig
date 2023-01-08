const std = @import("std");
const stb = @cImport({
    @cInclude("stb/stb_rect_pack.h");
    @cInclude("stb/stb_image.h");
});
const gl = @import("gl.zig");
const model = @import("model.zig");
const Rect = @import("geom.zig").Rect;
const Vec = @import("geom.zig").Vec;
const Program = @import("shaders.zig").Program;
const Viewport = @import("viewport.zig").Viewport;
const rendering = @import("rendering.zig");

pub const Sprite = struct {
    // region in texCoords space of the texture that needs to be displayed
    rect: Rect,
    angle: f32,
    z: model.Layer,
};

const SpriteSheetDescription = struct {
    spriteWidth: u16,
    spriteHeight: u16,
    angle: f32,
};

pub const SpriteFile = struct {
    content: []const u8,
    desc: SpriteSheetDescription,
};

pub const SpriteBitmap = struct {
    img: [*c]u8,
    width: usize,
    height: usize,
    desc: SpriteSheetDescription,
};

const atlasSize = 512;

pub const Atlas = struct {
    texture: gl.c.GLuint,
    sheets: []SpriteSheet,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        gl.c.glDeleteTextures(1, &self.texture);
        allocator.free(self.sheets);
    }
};

pub fn loadAtlas(allocator: std.mem.Allocator, sources: []const SpriteFile) !Atlas {
    const bitmaps = try loadBitmaps(allocator, sources);
    defer {
        for (bitmaps) |bitmap| {
            stb.stbi_image_free(bitmap.img);
        }
        allocator.free(bitmaps);
    }

    var context: stb.stbrp_context = undefined;
    var nodes = try allocator.alloc(stb.stbrp_node, 2048);
    defer allocator.free(nodes);
    stb.stbrp_init_target(&context, atlasSize, atlasSize, nodes.ptr, @intCast(c_int, nodes.len));

    var rects = try allocator.alloc(stb.stbrp_rect, sources.len);
    defer allocator.free(rects);
    for (rects) |*rect, i| {
        rect.h = @intCast(c_int, bitmaps[i].height);
        rect.w = @intCast(c_int, bitmaps[i].width);
        rect.id = @intCast(c_int, i);
    }
    if (stb.stbrp_pack_rects(&context, rects.ptr, @intCast(c_int, rects.len)) != 1) {
        std.log.err("rects: {any}", .{rects});
        @panic("atlas is too small");
    }
    std.log.debug("rects: {any}", .{rects});

    var atlas = try allocator.alloc(u8, 4 * atlasSize * atlasSize);
    defer allocator.free(atlas);
    for (bitmaps) |bitmap, i| {
        const x_offset = @intCast(usize, rects[i].x);
        const y_offset = @intCast(usize, rects[i].y);

        var y: usize = 0;
        while (y < bitmap.height) : (y += 1) {
            std.mem.copy(
                u8,
                atlas[x_offset + (y + y_offset) * atlasSize ..],
                bitmap.img[y * bitmap.width .. y * bitmap.width + bitmap.width * 4],
            );
        }
    }

    var texture: gl.c.GLuint = 0;
    gl.c.glGenTextures(1, &texture);
    gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, texture);
    defer gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, 0);

    gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_WRAP_S, gl.c.GL_CLAMP_TO_EDGE);
    gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_WRAP_T, gl.c.GL_CLAMP_TO_EDGE);
    gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MIN_FILTER, gl.c.GL_NEAREST_MIPMAP_NEAREST);
    gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MAG_FILTER, gl.c.GL_NEAREST_MIPMAP_NEAREST);
    gl.c.glTexImage2D(gl.c.GL_TEXTURE_2D, 0, gl.c.GL_RGBA, atlasSize, atlasSize, 0, gl.c.GL_RGBA, gl.c.GL_UNSIGNED_BYTE, atlas.ptr);
    gl.c.glGenerateMipmap(gl.c.GL_TEXTURE_2D);

    var sheets = try allocator.alloc(SpriteSheet, sources.len);
    for (sheets) |_, i| {
        sheets[i] = .{
            .xOffset = @intCast(u16, rects[i].x),
            .yOffset = @intCast(u16, rects[i].y),
            .width = @intCast(u16, bitmaps[i].width),
            .height = @intCast(u16, bitmaps[i].height),
            .spriteWidth = sources[i].desc.spriteWidth,
            .spriteHeight = sources[i].desc.spriteHeight,
            .angle = sources[i].desc.angle,
        };
    }

    return .{ .texture = texture, .sheets = sheets };
}

fn loadBitmaps(allocator: std.mem.Allocator, sources: []const SpriteFile) ![]SpriteBitmap {
    const result = try allocator.alloc(SpriteBitmap, sources.len);
    for (sources) |source, i| {
        var width: c_int = 0;
        var height: c_int = 0;
        var ch: c_int = 0;
        const img = stb.stbi_load_from_memory(@ptrCast([*c]const u8, source.content), @intCast(c_int, source.content.len), &width, &height, &ch, 4);
        std.debug.assert(ch == 4);

        std.log.debug("w {} h {} ch {}", .{ width, height, ch });
        result[i] = .{ .img = img, .width = @intCast(usize, width), .height = @intCast(usize, height), .desc = source.desc };
    }
    return result;
}

pub const SpriteSheet = struct {
    xOffset: u16,
    yOffset: u16,
    width: u16,
    height: u16,
    spriteWidth: u16,
    spriteHeight: u16,
    angle: f32,

    pub fn sprite(self: *const @This(), x: u16, y: u16, angle: f32, z: model.Layer) model.Sprite {
        const sz = Vec.initInt(self.spriteWidth, self.spriteHeight).div(Vec.initInt(self.width, self.height));

        return .{
            .rect = Rect.initSized(Vec.initInt(x, y).mul(sz), sz),
            .angle = angle + self.angle,
            .z = z,
        };
    }
};

// Renders rectangles with a given shader program.
pub const BatchSpriteRenderer = struct {
    const Uniforms = enum { model, projection, texScale, texOffset };

    rectRenderer: rendering.RectRenderer,
    program: Program(Uniforms),
    rects: std.ArrayList(gl.c.GLfloat),
    rectsBuffer: gl.c.GLuint,

    pub fn init(allocator: std.mem.Allocator) !BatchSpriteRenderer {
        const rectsBuffer = gl.genBuffer();
        const self = .{
            .rectRenderer = rendering.RectRenderer.init(),
            .program = try Program(Uniforms).init("shaders/batchSpriteVertex.glsl", "shaders/spriteFragment.glsl"),
            .rects = std.ArrayList(gl.c.GLfloat).init(allocator),
            .rectsBuffer = rectsBuffer,
        };
        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.rectRenderer.deinit();
        self.program.deinit();
        gl.c.glDeleteBuffers(1, &self.rectsBuffer);
        self.rects.deinit();
    }

    pub fn startFrame(self: *@This(), viewport: *Viewport) void {
        self.rectRenderer.startFrame(&self.program, viewport);
        self.rects.clearRetainingCapacity();
    }

    pub fn addSprite(self: *@This(), sprite: *const Sprite, rect: *const Rect) !void {
        try self.rects.append(rect.a.x);
        try self.rects.append(rect.a.y);
        try self.rects.append(rect.b.x);
        try self.rects.append(rect.b.y);

        _ = sprite;
    }

    pub fn render(self: *@This(), atlas: *Atlas) !void {
        self.program.use();
        _ = atlas;

        const rectsBuffer = self.rectsBuffer;

        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, rectsBuffer);
        gl.c.glBufferData(gl.c.GL_ARRAY_BUFFER, @intCast(gl.c.GLsizeiptr, self.rects.items.len * @sizeOf(gl.c.GLfloat)), self.rects.items.ptr, gl.c.GL_STATIC_DRAW);
        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, 0);

        gl.c.glBindVertexArray(self.rectRenderer.vao);
        defer gl.c.glBindVertexArray(0);

        gl.c.glEnableVertexAttribArray(1);
        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, rectsBuffer);
        gl.c.glVertexAttribPointer(1, 4, gl.c.GL_FLOAT, gl.c.GL_FALSE, 4 * @sizeOf(gl.c.GLfloat), null);
        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, 0);
        gl.c.glVertexAttribDivisor(1, 1);

        gl.c.glDrawArraysInstanced(gl.c.GL_TRIANGLES, 0, 6, @intCast(gl.c.GLint, self.rects.items.len / 4));
    }
};
