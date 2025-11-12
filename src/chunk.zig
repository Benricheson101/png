const std = @import("std");
const Allocator = std.mem.Allocator;
const Crc32 = std.hash.Crc32;
const zstd = std.compress.zstd;
const expectEqualSlices = std.testing.expectEqualSlices;

const c = @cImport({
    @cInclude("zlib.h");
});

// order is important here!
pub const ChunkType = enum(u8) {
    IHDR,
    // zTXt,
    tEXt,
    iTXt,
    // tIME,
    // sPLT,
    // pHYS,
    // sRGB,
    // sBIT,
    // iCCP,
    // gAMA,
    // cHRM,
    PLTE,
    // tRNS,
    // hIST,
    // bKGD,
    IDAT,
    IEND,
};

// TODO: can I somehow make a "CUSTOM" type in the enum that takes any type?
pub const Chunk = union(ChunkType) {
    IHDR: IHDR,
    tEXt: tEXt,
    iTXt: iTXt,
    PLTE: PLTE,
    IDAT: IDAT,
    IEND: IEND,
};

// for some reason the backing integer has struct fields in reverse order
pub const Color = packed struct(u24) {
    b: u8,
    g: u8,
    r: u8,
};

pub const IHDR = PNGChunk(.{ 'I', 'H', 'D', 'R' }, IHDRData);
pub const PLTE = PNGChunk(.{ 'P', 'L', 'T', 'E' }, PLTEData);
pub const IEND = PNGChunk(.{ 'I', 'E', 'N', 'D' }, IENDData);
pub const IDAT = PNGChunk(.{ 'I', 'D', 'A', 'T' }, IDATData);
pub const tEXt = PNGChunk(.{ 't', 'E', 'X', 't' }, TEXTData);
pub const iTXt = PNGChunk(.{ 'i', 'T', 'X', 't' }, ITXTData);

/// A generic PNG chunk
///
/// 4 bytes: data length
/// 4 bytes: chunk type
/// ? bytes: data
/// 4 bytes: crc32
fn PNGChunk(comptime chunk_type: [4]u8, comptime Data: type) type {
    const BASE_CHUNK_SIZE: usize = 12;

    return struct {
        data: Data,

        const Self = @This();

        pub fn init(data: Data) Self {
            return Self{
                .data = data,
            };
        }

        pub fn encode(self: *const Self, allocator: Allocator) ![]u8 {
            const data: []u8 = try self.data.encode(allocator);
            defer allocator.free(data);

            const buf = try allocator.alloc(u8, data.len + BASE_CHUNK_SIZE);
            @memset(buf[0..], 0);

            std.mem.writeInt(u32, buf[0..4], @intCast(data.len), .big);
            @memcpy(buf[4..8], chunk_type[0..4]);

            @memmove(buf[8 .. buf.len - 4], data[0..]);

            const crc = Crc32.hash(buf[4 .. buf.len - 4]);
            std.mem.writePackedInt(u32, buf[buf.len - 4 ..], 0, crc, .big);

            return buf;
        }
    };
}

pub const ColorType = enum(u8) {
    /// allowed bit depths: 1, 2, 4, 8, 16
    grayscale = 0,
    /// allowed bit depths: 8, 16
    truecolor = 2,
    /// allowed bit depths: 1, 2, 4, 8
    indexed = 3,
    /// allowed bit depths: 8, 16
    grayscale_alpha = 4,
    /// allowed bit depths: 8, 16
    truecolor_alpha = 6,
};

pub const IHDRData = struct {
    /// width of the image
    width: u32,
    /// height of the image
    height: u32,
    /// number of bits per sample (r/g/b) or per palette index (not per pixel). one of: 1, 2, 4, 8, 16
    bit_depth: u8 = 8,
    color_type: ColorType = .indexed,
    /// 0: deflate/inflate
    compression_method: u8 = 0,
    filter_method: u8 = 0,
    interlace_method: u8 = 0,

    pub fn length(_: *IHDRData) u32 {
        return 13;
    }

    fn encode(self: *const IHDRData, allocator: Allocator) ![]u8 {
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
    palette: []const Color,

    fn encode(self: *const PLTEData, allocator: Allocator) ![]u8 {
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
    fn encode(_: *const IENDData, _: Allocator) ![]u8 {
        return &[0]u8{};
    }
};

pub const IDATData = struct {
    image_data: []const u8,

    fn encode(self: *const IDATData, allocator: Allocator) ![]u8 {
        var comp_size = c.compressBound(self.image_data.len);

        var data = try allocator.alloc(u8, @intCast(comp_size));
        @memset(data[0..], 0);

        const df_status = c.compress(
            data.ptr,
            &comp_size,
            self.image_data.ptr,
            self.image_data.len,
        );

        if (df_status == c.Z_BUF_ERROR) {
            @panic("image data buffer is too small");
        }

        const buf = try allocator.alloc(u8, comp_size);
        @memmove(buf[0..comp_size], data[0..comp_size]);
        defer allocator.free(data);

        return buf;
    }
};

pub const TEXTData = struct {
    keyword: []const u8,
    str: []const u8,

    fn encode(self: *const TEXTData, allocator: Allocator) ![]u8 {
        const len = self.keyword.len + self.str.len + 1;
        var buf = try allocator.alloc(u8, len);
        @memset(buf[0..], 0);
        @memcpy(buf[0..self.keyword.len], self.keyword[0..]);
        @memcpy(buf[self.keyword.len + 1 .. len], self.str[0..self.str.len]);
        return buf;
    }
};

pub const ITXTData = struct {
    keyword: []const u8,
    /// 0=uncompressed, 1=compressed
    compression_flag: u8,
    /// 0=uncompressed or zlib
    compression_method: u8,
    language_tag: []const u8,
    /// translation of [keyword] in [language_tag]
    translated_keyword: []const u8,
    /// utf-8 text
    text: []const u8,

    fn encode(self: *const ITXTData, allocator: Allocator) ![]u8 {
        const len = self.keyword.len + self.language_tag.len + self.translated_keyword.len + self.text.len + 5;

        const buf = try allocator.alloc(u8, len);
        @memset(buf[0..], 0);
        var written: usize = 0;

        @memcpy(buf[0..self.keyword.len], self.keyword[0..]);
        written += self.keyword.len + 1; // +1 for \0
        buf[written] = self.compression_flag;
        buf[written + 1] = self.compression_method;
        written += 2;

        @memcpy(buf[written .. written + self.language_tag.len], self.language_tag[0..]);
        written += self.language_tag.len + 1;

        @memcpy(buf[written .. written + self.translated_keyword.len], self.translated_keyword[0..]);
        written += self.translated_keyword.len + 1;

        // TODO: compress if compression_flag = 1
        @memcpy(buf[written .. written + self.text.len], self.text[0..]);

        return buf;
    }
};

test "color packed struct" {
    const color = Color{ .r = 0x9c, .g = 0x9c, .b = 0xfc };

    const as_int: u24 = @bitCast(color);
    try std.testing.expectEqual(as_int, 0x9c9cfc);

    const new_color: Color = @bitCast(as_int);
    try std.testing.expectEqual(new_color, Color{ .r = 0x9c, .g = 0x9c, .b = 0xfc });
}

test "IHDR" {
    var hdr = Chunk{
        .IHDR = .init(.{ //
            .width = 16,
            .height = 16,
            .bit_depth = 8,
            .color_type = .indexed,
            .compression_method = 0,
            .filter_method = 0,
            .interlace_method = 0,
        }),
    };

    const data = [_]u8{
        0, 0, 0, 13, // length
        'I', 'H', 'D', 'R', // type
        0, 0, 0, 16, // width
        0, 0, 0, 16, // height
        8, // bit depth
        3, // color type
        0, // compression method
        0, // filter method
        0, // interlace method
        40, 45, 15, 83, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    var gpa = dbg_alloc.allocator();

    const encoded_data = try hdr.IHDR.encode(gpa);
    defer gpa.free(encoded_data);

    try expectEqualSlices(u8, data[0..], encoded_data[0..]);
}

test "PLTE" {
    var plte = Chunk{
        .PLTE = .init(.{
            .palette = &[_]Color{
                .{ .r = 0xff, .g = 0x00, .b = 0xaa },
                .{ .r = 0xcc, .g = 0xee, .b = 0x09 },
            },
        }),
    };

    const data = [_]u8{
        0, 0, 0, 6, // length
        'P', 'L', 'T', 'E', // type
        0xff, 0, 0xaa, // palette 0
        0xcc, 0xee, 0x09, // palette 0
        66, 225, 226, 128, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const encoded_data = try plte.PLTE.encode(gpa);
    defer gpa.free(encoded_data);

    try expectEqualSlices(u8, data[0..], encoded_data[0..]);
}

test "IDAT" {
    var idat = Chunk{
        .IDAT = .init(.{
            .image_data = &[_]u8{ 0, 1, 2, 3, 4 },
        }),
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const encoded_data = try idat.IDAT.encode(gpa);
    defer gpa.free(encoded_data);

    try expectEqualSlices(u8, "IDAT"[0..4], encoded_data[4..8]);
}

test "IEND" {
    var iend = Chunk{
        .IEND = .init(.{}),
    };

    const data = [_]u8{
        0, 0, 0, 0, // length
        'I', 'E', 'N', 'D', // type
        174, 66, 96, 130, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const encoded_data = try iend.IEND.encode(gpa);
    defer gpa.free(encoded_data);

    try expectEqualSlices(u8, data[0..], encoded_data[0..]);
}

test "tEXt" {
    var text = Chunk{
        .tEXt = .init(.{ //
            .keyword = "hi",
            .str = "hello",
        }),
    };

    const data = [_]u8{
        0, 0, 0, 8, // length
        't', 'E', 'X', 't', // type
        'h', 'i', // keyword
        0, // null separator
        'h', 'e', 'l', 'l', 'o', // str
        17, 24, 126, 143, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const encoded_data = try text.tEXt.encode(gpa);
    defer gpa.free(encoded_data);

    try expectEqualSlices(u8, data[0..], encoded_data[0..]);
}

test "iTXt" {
    var itxt = Chunk{
        .iTXt = .init(.{ //
            .keyword = "hi",
            .compression_flag = 0,
            .compression_method = 0,
            .language_tag = "en-us",
            .translated_keyword = "hi",
            .text = "heyyy",
        }),
    };

    const data = [_]u8{
        0, 0, 0, 19, // length
        'i', 'T', 'X', 't', // type
        'h', 'i', // keyword
        0, // null separator
        0, // compression flag
        0, // compression method
        'e', 'n', '-', 'u', 's', // language tag
        0, // null separator
        'h', 'i', // translated keyword
        0, // null separator
        'h', 'e', 'y', 'y', 'y', // text
        107, 0, 47, 125, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const encoded_data = try itxt.iTXt.encode(gpa);
    defer gpa.free(encoded_data);

    try expectEqualSlices(u8, data[0..], encoded_data[0..]);
}
