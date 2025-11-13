const std = @import("std");
const chunk = @import("../chunk.zig");

const Allocator = std.mem.Allocator;
const Chunk = chunk.Chunk;
const PNGChunk = chunk.PNGChunk;

pub const IEND = PNGChunk(.{ 'I', 'E', 'N', 'D' }, IENDData);

pub const IENDData = struct {
    pub fn encode(_: *const IENDData, _: Allocator) ![]u8 {
        return &[0]u8{};
    }

    pub fn decode(_: []u8, _: chunk.DecoderContext, _: Allocator) !@This() {
        return IENDData{};
    }
};

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

    try std.testing.expectEqualSlices(u8, data[0..], encoded_data[0..]);
}

test "IEND decode" {
    var data = [_]u8{
        0, 0, 0, 0, // length
        'I', 'E', 'N', 'D', // type
        174, 66, 96, 130, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const iend_chunk = try Chunk.decode(&data, .{}, gpa);

    try std.testing.expectEqual(iend_chunk, .IEND);
}
