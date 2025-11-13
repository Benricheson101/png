const std = @import("std");
const Allocator = std.mem.Allocator;
const Crc32 = std.hash.Crc32;
const zstd = std.compress.zstd;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqual = std.testing.expectEqual;

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

pub const DecoderContext = struct {
    header: ?IHDRData = null,
};

// TODO: can I somehow make a "CUSTOM" type in the enum that takes any type?
pub const Chunk = union(ChunkType) {
    IHDR: IHDR,
    tEXt: tEXt,
    iTXt: iTXt,
    PLTE: PLTE,
    IDAT: IDAT,
    IEND: IEND,

    pub fn decode(buf: []u8, ctx: DecoderContext, allocator: Allocator) !Chunk {
        const len_bytes = buf[0..4];
        // const len: u32 = @intFromPtr(len_bytes);
        const len = std.mem.readInt(u32, len_bytes, .big);

        const typ = buf[4..8];
        const data = buf[8 .. len + 8];
        const crc_bytes = buf[len + 8 .. len + 12];
        const crc = std.mem.readPackedInt(u32, crc_bytes, 0, .big);

        const actual_crc = Crc32.hash(buf[4 .. len + 8]);
        if (crc != actual_crc) {
            return error.BadChecksum;
        }

        const thing = std.meta.stringToEnum(ChunkType, typ[0..]);
        if (thing) |ty| {
            return switch (ty) {
                .IHDR => .{ .IHDR = try IHDR.decode(data, ctx, allocator) },
                .PLTE => .{ .PLTE = try PLTE.decode(data, ctx, allocator) },
                .IEND => .{ .IEND = try IEND.decode(data, ctx, allocator) },
                .IDAT => .{ .IDAT = try IDAT.decode(data, ctx, allocator) },
                .tEXt => .{ .tEXt = try tEXt.decode(data, ctx, allocator) },
                .iTXt => .{ .iTXt = try iTXt.decode(data, ctx, allocator) },
                // else => return error.Unimplemented,
            };
        } else {
            return error.BadChunkType;
        }
    }

    // TODO: deinit
};

// for some reason the backing integer has struct fields in reverse order
pub const Color = packed struct(u24) {
    b: u8,
    g: u8,
    r: u8,

    fn toBytes(self: Color) [3]u8 {
        const color: u24 = @bitCast(self);
        var buf: [3]u8 = undefined;
        std.mem.writeInt(u24, buf[0..3], color, .big);
        return buf;
    }

    fn fromBytes(buf: []const u8) Color {
        const nr = std.mem.readInt(u24, buf[0..3], .big);
        return @bitCast(nr);
    }
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
fn PNGChunk(comptime chunk_typ: [4]u8, comptime Data: type) type {
    const BASE_CHUNK_SIZE: usize = 12;

    return struct {
        pub const chunk_type = chunk_typ;
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
            @memcpy(buf[4..8], chunk_typ[0..4]);

            @memmove(buf[8 .. buf.len - 4], data[0..]);

            const crc = Crc32.hash(buf[4 .. buf.len - 4]);
            std.mem.writePackedInt(u32, buf[buf.len - 4 ..], 0, crc, .big);

            return buf;
        }

        pub fn decode(data: []u8, ctx: DecoderContext, allocator: Allocator) !Self {
            return Self{
                .data = try Data.decode(data, ctx, allocator),
            };
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

    fn decode(data: []u8, _: DecoderContext, _: Allocator) !@This() {
        if (data.len != 13) {
            return error.BadHdr;
        }

        return IHDRData{
            .width = std.mem.readInt(u32, data[0..4], .big),
            .height = std.mem.readInt(u32, data[4..8], .big),
            .bit_depth = data[8],
            .color_type = @enumFromInt(data[9]),
            .compression_method = data[10],
            .filter_method = data[11],
            .interlace_method = data[12],
        };
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

    fn decode(data: []u8, _: DecoderContext, allocator: Allocator) !@This() {
        if (data.len % 3 != 0) {
            return error.BadChunkData;
        }

        const n_colors = data.len / 3;
        var colors = try allocator.alloc(Color, n_colors);

        var n: usize = 0;
        var i: usize = 0;
        while (i < n_colors) : (n += 3) {
            const byt = data[n .. n + 3];
            const color = Color.fromBytes(byt);
            colors[i] = color;
            i += 1;
        }

        return PLTEData{
            .palette = colors,
        };
    }
};

pub const IENDData = struct {
    fn encode(_: *const IENDData, _: Allocator) ![]u8 {
        return &[0]u8{};
    }

    fn decode(_: []u8, _: DecoderContext, _: Allocator) !@This() {
        return IENDData{};
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

    fn decode(data: []u8, ctx: DecoderContext, allocator: Allocator) !@This() {
        const hdr = ctx.header orelse @panic("IHDR must be decoded before IDAT");

        const pixel_size: usize = if (hdr.color_type == .indexed) 1 else 3;
        const max_buf_size = (hdr.width + 1) * hdr.height * pixel_size;

        const buf = try allocator.alloc(u8, max_buf_size);

        // return buf;

        var decomp_size: c_ulong = max_buf_size;

        const status = c.uncompress(buf.ptr, &decomp_size, data.ptr, data.len);

        if (status == c.Z_BUF_ERROR) {
            @panic("failed to uncompress image data");
        }

        return IDATData{
            .image_data = buf[0..decomp_size],
        };
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

    fn decode(data: []u8, _: DecoderContext, _: Allocator) !@This() {
        var keyword_len: usize = 0;
        while (data[keyword_len] != 0) : (keyword_len += 1) {}

        return TEXTData{
            .keyword = data[0..keyword_len],
            .str = data[keyword_len + 1 ..],
        };
    }
};

pub const ITXTData = struct {
    keyword: []const u8,
    /// 0=uncompressed, 1=compressed
    compression_flag: u8 = 0,
    /// 0=uncompressed or zlib
    compression_method: u8 = 0,
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

    fn decodeStr(buf: []u8) []u8 {
        var i: usize = 0;
        while (buf[i] != 0) : (i += 1) {}
        return buf[0..i];
    }

    fn decode(data: []u8, _: DecoderContext, _: Allocator) !@This() {
        var cursor: usize = 0;

        const keyword = decodeStr(data[cursor..]);
        cursor += keyword.len + 1;

        const compression_flag = data[cursor];
        cursor += 1;
        const compression_method = data[cursor];
        cursor += 1;

        const language_tag = decodeStr(data[cursor..]);
        cursor += language_tag.len + 1;

        const translated_keyword = decodeStr(data[cursor..]);
        cursor += translated_keyword.len + 1;

        const text = data[cursor..];

        return .{
            .keyword = keyword,
            .compression_flag = compression_flag,
            .compression_method = compression_method,
            .language_tag = language_tag,
            .translated_keyword = translated_keyword,
            .text = text,
        };
    }
};

test "color packed struct" {
    const color = Color{ .r = 0x9c, .g = 0x9c, .b = 0xfc };

    const as_int: u24 = @bitCast(color);
    try std.testing.expectEqual(as_int, 0x9c9cfc);

    const new_color: Color = @bitCast(as_int);
    try std.testing.expectEqual(new_color, Color{ .r = 0x9c, .g = 0x9c, .b = 0xfc });
}

test "color toBytes" {
    const color = Color{ .r = 0x9c, .g = 0x9c, .b = 0xfc };
    const bytes = color.toBytes();

    try expectEqualSlices(u8, &[_]u8{ 0x9c, 0x9c, 0xfc }, bytes[0..]);
}

test "color fromBytes" {
    const color_code = [3]u8{ 0x9c, 0x9c, 0xfc };
    const color = Color.fromBytes(color_code[0..]);

    try expectEqual(Color{ .r = 0x9c, .g = 0x9c, .b = 0xfc }, color);
}

test "IHDR encode" {
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

test "IHDR decode" {
    var data = [_]u8{
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
    const gpa = dbg_alloc.allocator();

    const ihdr = try Chunk.decode(&data, .{}, gpa);
    const ihdr_data = ihdr.IHDR.data;

    try expectEqual(ihdr_data.width, 16);
    try expectEqual(ihdr_data.height, 16);
    try expectEqual(ihdr_data.bit_depth, 8);
    try expectEqual(ihdr_data.color_type, .indexed);
    try expectEqual(ihdr_data.compression_method, 0);
    try expectEqual(ihdr_data.filter_method, 0);
    try expectEqual(ihdr_data.interlace_method, 0);
}

test "PLTE encode" {
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

test "PLTE decode" {
    var data = [_]u8{
        0, 0, 0, 6, // length
        'P', 'L', 'T', 'E', // type
        0xff, 0, 0xaa, // palette 0
        0xcc, 0xee, 0x09, // palette 1
        66, 225, 226, 128, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const chunk = try Chunk.decode(&data, .{}, gpa);
    const palette = chunk.PLTE.data.palette;
    defer gpa.free(palette);

    try expectEqual(Color{ .r = 0xff, .g = 0x00, .b = 0xaa }, palette[0]);
    try expectEqual(Color{ .r = 0xcc, .g = 0xee, .b = 0x09 }, palette[1]);
}

test "IDAT encode" {
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

test "IDAT decode" {
    const ctx = DecoderContext{
        .header = .{
            .width = 9,
            .height = 9,
            .color_type = .indexed,
        },
    };

    var data = [_]u8{
        0, 0, 0, 30, // length
        'I', 'D', 'A', 'T', // type
        120, 156, 99, 96, 64, 0, 70, 70, 16, 102, 100, 128, 147, 40, 44, 6, 4, 15, 204, 197, 84, 7, 225, 193, 0, 0, 5, 99, 0, // data
        30, 188, 189, 243, 225, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const chunk = try Chunk.decode(&data, ctx, gpa);
    defer gpa.free(chunk.IDAT.data.image_data);

    const expected_data = [_]u8{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 1, 1, 0, 0, 1, 1, 1, 0,
        0, 0, 1, 1, 1, 0, 0, 0, 1, 0,
        0, 0, 1, 1, 1, 0, 0, 0, 1, 0,
        0, 0, 0, 0, 0, 0, 1, 1, 1, 0,
        0, 0, 1, 1, 0, 0, 0, 0, 1, 0,
        0, 0, 1, 1, 1, 0, 0, 0, 1, 0,
        0, 0, 1, 1, 1, 0, 1, 1, 1, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    };

    try expectEqualSlices(u8, expected_data[0..], chunk.IDAT.data.image_data[0..]);
}

test "IEND encode" {
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

test "tEXt encode" {
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

test "tEXt decode" {
    var data = [_]u8{
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

    const chunk = try Chunk.decode(&data, .{}, gpa);

    try expectEqualSlices(u8, &[_]u8{ 'h', 'i' }, chunk.tEXt.data.keyword);
    try expectEqualSlices(u8, &[_]u8{ 'h', 'e', 'l', 'l', 'o' }, chunk.tEXt.data.str);
}

test "iTXt encode" {
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

test "iTXt decode" {
    var data = [_]u8{
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

    const chunk = try Chunk.decode(&data, .{}, gpa);

    try expectEqualSlices(u8, &[_]u8{ 'h', 'i' }, chunk.iTXt.data.keyword[0..]);
    try expectEqualSlices(u8, &[_]u8{ 'e', 'n', '-', 'u', 's' }, chunk.iTXt.data.language_tag[0..]);
    try expectEqualSlices(u8, &[_]u8{ 'h', 'i' }, chunk.iTXt.data.translated_keyword[0..]);
    try expectEqualSlices(u8, &[_]u8{ 'h', 'e', 'y', 'y', 'y' }, chunk.iTXt.data.text[0..]);
}
