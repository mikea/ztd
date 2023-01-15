const std = @import("std");
const builtin = @import("builtin");
const stb = @cImport({
    @cInclude("stb/stb_rect_pack.h");
    @cInclude("stb/stb_image.h");
    @cInclude("stb/stb_image_write.h");
});
const gl = @import("gl.zig");
const model = @import("model.zig");
const Rect = @import("geom.zig").Rect;
const Vec = @import("geom.zig").Vec;
const Program = @import("shaders.zig").Program;
const Viewport = @import("viewport.zig").Viewport;
const rendering = @import("rendering.zig");

pub const Sprite = struct {
    texRect: Rect,
    angle: f32,
    z: model.Layer,
};

const SpriteSheetDescription = struct {
    spriteWidth: u16,
    spriteHeight: u16,
    angle: f32,
    xOffset: u16 = 0,
    yOffset: u16 = 0,
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

pub const SpriteSheet = struct {
    atlasOffset: Vec,
    desc: SpriteSheetDescription,

    pub fn sprite(self: *const @This(), x: u16, y: u16, angle: f32, z: model.Layer) model.Sprite {
        const origin = self.atlasOffset
            .add(Vec.init(x * self.desc.spriteWidth, y * self.desc.spriteHeight))
            .add(Vec.init(self.desc.xOffset, self.desc.yOffset))
            .div(atlasSize);
        const size = Vec.init(self.desc.spriteWidth, self.desc.spriteHeight).div(atlasSize);
        const texRect = Rect.initSized(origin, size);
        return .{ .texRect = texRect, .angle = angle + self.desc.angle, .z = z };
    }
};

const atlasDim = 512;
const atlasSize = Vec.init(atlasDim, atlasDim);

pub const Atlas = struct {
    texture: gl.c.GLuint,
    sheets: []SpriteSheet,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        gl.c.glDeleteTextures(1, &self.texture);
        allocator.free(self.sheets);
    }
};

pub fn loadAtlas(allocator: std.mem.Allocator, sources: []const SpriteFile) !Atlas {
    try std.io.getStdOut().writer().print("building sprites atlas...", .{});
    // load bitmaps
    const bitmaps = try loadBitmaps(allocator, sources);
    defer {
        for (bitmaps) |bitmap| {
            stb.stbi_image_free(bitmap.img);
        }
        allocator.free(bitmaps);
    }

    // init rect packer
    var context: stb.stbrp_context = undefined;
    var nodes = try allocator.alloc(stb.stbrp_node, atlasDim * 4);
    defer allocator.free(nodes);
    stb.stbrp_init_target(&context, atlasDim, atlasDim, nodes.ptr, @intCast(c_int, nodes.len));

    // pack bitmaps
    var rects = try allocator.alloc(stb.stbrp_rect, sources.len);
    defer allocator.free(rects);
    for (rects) |*rect, i| {
        rect.w = @intCast(c_int, bitmaps[i].width);
        rect.h = @intCast(c_int, bitmaps[i].height);
        rect.id = @intCast(c_int, i);
    }
    if (stb.stbrp_pack_rects(&context, rects.ptr, @intCast(c_int, rects.len)) != 1) {
        std.log.err("rects: {any}", .{rects});
        @panic("atlas is too small");
    }

    // allocate atlas
    const atlasRowSize = 4 * atlasDim;
    var atlas = try allocator.alloc(u8, atlasRowSize * atlasDim);
    defer allocator.free(atlas);
    std.mem.set(u8, atlas, 0);

    // render bitmaps into atlas using packing info
    for (bitmaps) |bitmap, i| {
        std.debug.assert(rects[i].was_packed == 1);
        std.debug.assert(rects[i].id == i);
        const x_offset = @intCast(usize, rects[i].x);
        const y_offset = @intCast(usize, rects[i].y);
        const rowSize = bitmap.width * 4;

        var y: usize = 0;
        while (y < bitmap.height) : (y += 1) {
            std.mem.copy(
                u8,
                atlas[x_offset * 4 + (y + y_offset) * atlasRowSize ..],
                bitmap.img[y * rowSize .. y * rowSize + rowSize],
            );
        }
    }

    if (builtin.mode == .Debug) {
        if (stb.stbi_write_png("/tmp/atlas.png", atlasDim, atlasDim, 4, atlas.ptr, atlasRowSize) != 1) {
            @panic("error writing atlas");
        }
    }

    // prepare opengl texture
    var texture: gl.c.GLuint = 0;
    gl.c.glGenTextures(1, &texture);
    gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, texture);
    defer gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, 0);
    gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_WRAP_S, gl.c.GL_CLAMP_TO_EDGE);
    gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_WRAP_T, gl.c.GL_CLAMP_TO_EDGE);
    gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MIN_FILTER, gl.c.GL_NEAREST_MIPMAP_LINEAR);
    gl.c.glTexParameteri(gl.c.GL_TEXTURE_2D, gl.c.GL_TEXTURE_MAG_FILTER, gl.c.GL_NEAREST);
    gl.c.glTexImage2D(gl.c.GL_TEXTURE_2D, 0, gl.c.GL_RGBA, atlasDim, atlasDim, 0, gl.c.GL_RGBA, gl.c.GL_UNSIGNED_BYTE, atlas.ptr);
    gl.c.glGenerateMipmap(gl.c.GL_TEXTURE_2D);

    // store individual sheet information
    var sheets = try allocator.alloc(SpriteSheet, sources.len);
    for (sheets) |_, i| {
        sheets[i] = .{ .atlasOffset = Vec.init(rects[i].x, rects[i].y), .desc = sources[i].desc };
    }
    try std.io.getStdOut().writer().print("done.\n", .{});

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
        result[i] = .{ .img = img, .width = @intCast(usize, width), .height = @intCast(usize, height), .desc = source.desc };
    }
    return result;
}

// Renders rectangles with a given shader program.
pub const BatchSpriteRenderer = struct {
    const Uniforms = enum { model, projection, texScale, texOffset };

    rectRenderer: rendering.RectRenderer,
    program: Program(Uniforms),

    rects: std.ArrayList([4]gl.c.GLfloat),
    rectsBuffer: gl.c.GLuint,

    texRects: std.ArrayList([4]gl.c.GLfloat),
    texRectsBuffer: gl.c.GLuint,

    angleLayer: std.ArrayList([2]gl.c.GLfloat),
    angleLayerBuffer: gl.c.GLuint,

    pub fn init(allocator: std.mem.Allocator) !BatchSpriteRenderer {
        const self = .{
            .rectRenderer = rendering.RectRenderer.init(),
            .program = try Program(Uniforms).init("shaders/batchSpriteVertex.glsl", "shaders/spriteFragment.glsl"),
            .rects = std.ArrayList([4]gl.c.GLfloat).init(allocator),
            .rectsBuffer = gl.genBuffer(),
            .texRects = std.ArrayList([4]gl.c.GLfloat).init(allocator),
            .texRectsBuffer = gl.genBuffer(),
            .angleLayer = std.ArrayList([2]gl.c.GLfloat).init(allocator),
            .angleLayerBuffer = gl.genBuffer(),
        };
        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.rectRenderer.deinit();
        self.program.deinit();
        self.rects.deinit();
        self.texRects.deinit();
        self.angleLayer.deinit();
        gl.c.glDeleteBuffers(1, &self.rectsBuffer);
    }

    pub fn startFrame(self: *@This(), viewport: *Viewport) void {
        self.rectRenderer.startFrame(&self.program, viewport);
        self.rects.clearRetainingCapacity();
        self.texRects.clearRetainingCapacity();
        self.angleLayer.clearRetainingCapacity();
    }

    pub fn addSprite(self: *@This(), id: model.Id, sprite: *const Sprite, rect: *const Rect) !void {
        const z = -@intToFloat(f32, @enumToInt(sprite.z)) / @intToFloat(f32, @typeInfo(model.Layer).Enum.fields.len) +
            @intToFloat(f32, id) / @intToFloat(f32, model.maxId) / 10;

        try self.rects.append([_]gl.c.GLfloat{ rect.a.x, rect.a.y, rect.b.x, rect.b.y });
        try self.texRects.append([_]gl.c.GLfloat{ sprite.texRect.a.x, sprite.texRect.a.y, sprite.texRect.b.x, sprite.texRect.b.y });
        try self.angleLayer.append([_]gl.c.GLfloat{ sprite.angle, z });
    }

    pub fn render(self: *@This(), atlas: *Atlas) !void {
        self.program.use();

        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, self.rectsBuffer);
        gl.c.glBufferData(gl.c.GL_ARRAY_BUFFER, @intCast(gl.c.GLsizeiptr, 4 * self.rects.items.len * @sizeOf(gl.c.GLfloat)), self.rects.items.ptr, gl.c.GL_STATIC_DRAW);
        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, 0);

        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, self.texRectsBuffer);
        gl.c.glBufferData(gl.c.GL_ARRAY_BUFFER, @intCast(gl.c.GLsizeiptr, 4 * self.texRects.items.len * @sizeOf(gl.c.GLfloat)), self.texRects.items.ptr, gl.c.GL_STATIC_DRAW);
        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, 0);

        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, self.angleLayerBuffer);
        gl.c.glBufferData(gl.c.GL_ARRAY_BUFFER, @intCast(gl.c.GLsizeiptr, 2 * self.angleLayer.items.len * @sizeOf(gl.c.GLfloat)), self.angleLayer.items.ptr, gl.c.GL_STATIC_DRAW);
        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, 0);

        // 0
        gl.c.glBindVertexArray(self.rectRenderer.vao);
        defer gl.c.glBindVertexArray(0);

        // 1 - rects
        gl.c.glEnableVertexAttribArray(1);
        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, self.rectsBuffer);
        gl.c.glVertexAttribPointer(1, 4, gl.c.GL_FLOAT, gl.c.GL_FALSE, 4 * @sizeOf(gl.c.GLfloat), null);
        gl.c.glVertexAttribDivisor(1, 1);
        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, 0);

        // 2 - angle + layer
        gl.c.glEnableVertexAttribArray(2);
        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, self.angleLayerBuffer);
        gl.c.glVertexAttribPointer(2, 2, gl.c.GL_FLOAT, gl.c.GL_FALSE, 2 * @sizeOf(gl.c.GLfloat), null);
        gl.c.glVertexAttribDivisor(2, 1);
        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, 0);

        // 3 - texRects
        gl.c.glEnableVertexAttribArray(3);
        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, self.texRectsBuffer);
        gl.c.glVertexAttribPointer(3, 4, gl.c.GL_FLOAT, gl.c.GL_FALSE, 4 * @sizeOf(gl.c.GLfloat), null);
        gl.c.glVertexAttribDivisor(3, 1);
        gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, 0);

        gl.c.glActiveTexture(gl.c.GL_TEXTURE0);
        gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, atlas.texture);
        defer gl.c.glBindTexture(gl.c.GL_TEXTURE_2D, 0);

        gl.c.glDrawArraysInstanced(gl.c.GL_TRIANGLES, 0, 6, @intCast(gl.c.GLint, self.rects.items.len));
    }
};
