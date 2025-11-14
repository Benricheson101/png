const std = @import("std");
const chunk = @import("../chunk.zig");

const Allocator = std.mem.Allocator;
const Chunk = chunk.Chunk;
const PNGChunk = chunk.PNGChunk;

pub const sRGB = PNGChunk("sRGB".*, SRGBData);

pub const RenderingIntent = enum(u8) {
    /// Perceptual intent is for images preferring good adaptation to the output device gamut at the expense of colorimetric accuracy, like photographs.
    perceptual = 0,
    /// Relative colorimetric intent is for images requiring color appearance matching (relative to the output device white point), like logos.
    relative_colorimetric = 1,
    /// Saturation intent is for images preferring preservation of saturation at the expense of hue and lightness, like charts and graphs.
    saturation = 2,
    /// Absolute colorimetric intent is for images requiring preservation of absolute colorimetry, like proofs (previews of images destined for a different output device).
    absolute_colorimetric = 3,
};

pub const SRGBData = struct {
    intent: RenderingIntent,

    pub fn encode(self: *const SRGBData, allocator: Allocator) ![]u8 {
        var buf = try allocator.alloc(u8, 1);
        buf[0] = @intFromEnum(self.intent);
        return buf;
    }

    pub fn decode(data: []u8, _: chunk.DecoderContext, _: Allocator) !@This() {
        const intent: RenderingIntent = @enumFromInt(data[0]);
        return SRGBData{
            .intent = intent,
        };
    }
};

test "sRGB encode" {
    var srgb = Chunk{
        .sRGB = .init(.{
            .intent = .relative_colorimetric
        }),
    };

    const data = [_]u8{
        0, 0, 0, 1, // length
        's', 'R', 'G', 'B', // type
        1, // intent
        217, 201, 44, 127, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const encoded_data = try srgb.sRGB.encode(gpa);
    defer gpa.free(encoded_data);

    try std.testing.expectEqualSlices(u8, data[0..], encoded_data[0..]);
}

test "sRGB decode" {
    var data = [_]u8{
        0, 0, 0, 1, // length
        's', 'R', 'G', 'B', // type
        1, // intent
        217, 201, 44, 127, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const srgb_chunk = try Chunk.decode(&data, .{}, gpa);

    try std.testing.expectEqual(srgb_chunk.sRGB.data.intent, .relative_colorimetric);
}
