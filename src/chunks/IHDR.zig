const std = @import("std");
const chunk = @import("../chunk.zig");

const Allocator = std.mem.Allocator;
const Chunk = chunk.Chunk;
const PNGChunk = chunk.PNGChunk;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqual = std.testing.expectEqual;

pub const IHDR = PNGChunk(.{ 'I', 'H', 'D', 'R' }, IHDRData);

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

    pub fn encode(self: *const IHDRData, allocator: Allocator) ![]u8 {
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

    pub fn decode(data: []u8, _: chunk.DecoderContext, _: Allocator) !@This() {
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
