const std = @import("std");

pub const ihdr = @import("./chunks/IHDR.zig");
pub const plte = @import("./chunks/PLTE.zig");
pub const iend = @import("./chunks/IEND.zig");
pub const idat = @import("./chunks/IDAT.zig");
pub const text = @import("./chunks/tEXt.zig");
pub const itxt = @import("./chunks/iTXt.zig");
pub const trns = @import("./chunks/tRNS.zig");
pub const srgb = @import("./chunks/sRGB.zig");

// pub const simple_ancillary = @import("./chunks/simple.zig");

const Allocator = std.mem.Allocator;
const Crc32 = std.hash.Crc32;

// order is important here!
pub const ChunkType = enum(u8) {
    IHDR,
    // zTXt,
    tEXt,
    iTXt,
    // tIME,
    // sPLT,
    // pHYS,
    sRGB,
    // sBIT,
    // iCCP,
    // gAMA,
    // cHRM,
    PLTE,
    tRNS,
    // hIST,
    // bKGD,
    IDAT,
    IEND,
};

pub const DecoderContext = struct {
    header: ?ihdr.IHDRData = null,
};

// TODO: can I somehow make a "CUSTOM" type in the enum that takes any type?
pub const Chunk = union(ChunkType) {
    IHDR: ihdr.IHDR,
    tEXt: text.tEXt,
    iTXt: itxt.iTXt,
    sRGB: srgb.sRGB,
    PLTE: plte.PLTE,
    tRNS: trns.tRNS,
    IDAT: idat.IDAT,
    IEND: iend.IEND,

    pub fn decode(buf: []u8, ctx: DecoderContext, allocator: Allocator) !Chunk {
        const len_bytes = buf[0..4];
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
        if (thing == null) {
            return error.UnknownChunk;
        }

        return switch (thing.?) {
            .IHDR => .{ .IHDR = try ihdr.IHDR.decode(data, ctx, allocator) },
            .PLTE => .{ .PLTE = try plte.PLTE.decode(data, ctx, allocator) },
            .IEND => .{ .IEND = try iend.IEND.decode(data, ctx, allocator) },
            .IDAT => .{ .IDAT = try idat.IDAT.decode(data, ctx, allocator) },
            .tEXt => .{ .tEXt = try text.tEXt.decode(data, ctx, allocator) },
            .iTXt => .{ .iTXt = try itxt.iTXt.decode(data, ctx, allocator) },
            .tRNS => .{ .tRNS = try trns.tRNS.decode(data, ctx, allocator) },
            .sRGB => .{ .sRGB = try srgb.sRGB.decode(data, ctx, allocator) },
            // else => return error.Unimplemented,
        };
    }

    // TODO: deinit
};

/// A generic PNG chunk
///
/// 4 bytes: data length
/// 4 bytes: chunk type
/// ? bytes: data
/// 4 bytes: crc32

pub fn PNGChunk(comptime chunk_typ: [4]u8, comptime Data: type) type {
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
