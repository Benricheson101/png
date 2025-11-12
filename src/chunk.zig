const std = @import("std");
const Allocator = std.mem.Allocator;
const Crc32 = std.hash.Crc32;
const zstd = std.compress.zstd;

const c = @cImport({
    @cInclude("zlib.h");
});

pub const Chunk = union {
    IHDR: IHDR,
    PLTE: PLTE,
    IDAT: IDAT,
    IEND: IEND,
};

pub const IHDR = PNGChunk(.{ 73, 72, 68, 82 }, IHDRData);
pub const PLTE = PNGChunk(.{ 80, 76, 84, 69 }, PLTEData);
pub const IEND = PNGChunk(.{ 73, 69, 78, 68 }, IENDData);
pub const IDAT = PNGChunk(.{ 73, 68, 65, 84 }, IDATData);

// TODO: does this have anything to do with endianess? the docs make it look like it may but someone on reddit said that was a mistake

// for some reason the backing integer has struct fields in reverse order
pub const Color = packed struct(u24) {
    b: u8,
    g: u8,
    r: u8,
};

/// A generic PNG chunk
///
/// 4 bytes: data length
/// 4 bytes: chunk type
/// ? bytes: data
/// 4 bytes: crc32
fn PNGChunk(comptime chunk_typ: [4]u8, comptime Data: type) type {
    const BASE_CHUNK_SIZE: usize = 12;

    return struct {
        data: Data,

        const Self = @This();

        pub fn encode(self: *Self, allocator: Allocator) ![]u8 {
            const data: []u8 = try self.data.encode(allocator);
            defer allocator.free(data);

            const buf = try allocator.alloc(u8, data.len + BASE_CHUNK_SIZE);
            @memset(buf[0..], 0);

            std.mem.writeInt(u32, buf[0..4], @intCast(data.len), .big);
            // TODO: should this be memmove? waht's the difference in this case
            @memcpy(buf[4..8], chunk_typ[0..4]);

            @memmove(buf[8 .. buf.len - 4], data[0..]);

            const crc = Crc32.hash(buf[4 .. buf.len - 4]);
            std.mem.writePackedInt(u32, buf[buf.len - 4 ..], 0, crc, .big);

            return buf;
        }
    };
}

pub const ColorType = enum(u8) {
    /// allowed bit depths: 1, 2, 4, 8, 16
    Grayscale = 0,
    /// allowed bit depths: 8, 16
    True = 2,
    /// allowed bit depths: 1, 2, 4, 8
    Indexed = 3,
    /// allowed bit depths: 8, 16
    GrayscaleAlpha = 4,
    /// allowed bit depths: 8, 16
    TrueAlpha = 6,
};

pub const IHDRData = struct {
    /// width of the image
    width: u32,
    /// height of the image
    height: u32,
    /// number of bits per sample (r/g/b) or per palette index (not per pixel). one of: 1, 2, 4, 8, 16
    bit_depth: u8,
    color_type: ColorType,
    /// 0: deflate/inflate
    compression_method: u8,
    filter_method: u8,
    interlace_method: u8,

    pub fn length(_: *IHDRData) u32 {
        return 13;
    }

    fn encode(self: *IHDRData, allocator: Allocator) ![]u8 {
        var buf = try allocator.alloc(u8, 13);
        @memset(buf[0..], 0);

        std.mem.writeInt(u32, buf[0..4], self.width, .big);
        std.mem.writeInt(u32, buf[4..8], self.height, .big);
        buf[8] = self.bit_depth;
        buf[9] = @intFromEnum(self.color_type);
        buf[10] = self.compression_method;
        buf[11] = self.filter_method;
        buf[12] = self.interlace_method;

        return buf;
    }
};

pub const PLTEData = struct {
    palette: []Color,

    fn encode(self: *PLTEData, allocator: Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, self.palette.len * 3);
        @memset(buf[0..], 0);

        for (self.palette, 0..) |color, i| {
            const bytes: u24 = @bitCast(color);
            std.mem.writePackedInt(u24, buf[(i * 3) .. (i * 3) + 3], 0, bytes, .big);
        }

        return buf;
    }
};

pub const IENDData = struct {
    fn encode(_: *IENDData, _: Allocator) ![]u8 {
        return &[0]u8{};
    }
};

pub const IDATData = struct {
    image_data: []u8,

    fn encode(self: *IDATData, allocator: Allocator) ![]u8 {
        var comp_size = c.compressBound(self.image_data.len);
        var data = try allocator.alloc(u8, @intCast(comp_size));
        @memset(data[0..], 0);

        const df_status = c.compress(data.ptr, &comp_size, self.image_data.ptr, self.image_data.len);

        if (df_status == c.Z_BUF_ERROR) {
            @panic("image data buffer is too small");
        }

        const buf = try allocator.alloc(u8, comp_size);
        @memmove(buf[0..comp_size], data[0..comp_size]);
        defer allocator.free(data);

        std.debug.print("compressed size: {d}\n", .{comp_size});

        return buf;
    }
};

test "color packed struct" {
    const color = Color{ .r = 0x9c, .g = 0x9c, .b = 0xfc };

    const as_int: u24 = @bitCast(color);
    try std.testing.expectEqual(as_int, 0x9c9cfc);
}
