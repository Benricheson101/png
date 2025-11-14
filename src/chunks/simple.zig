const std = @import("std");
const chunk = @import("../chunk.zig");

const Allocator = std.mem.Allocator;

pub const SimpleChunkData = struct {
    data: []const u8,

    pub fn encode(self: *const SimpleChunkData, allocator: Allocator) ![]u8 {
        var buf = try allocator.alloc(u8, self.data.len);
        @memcpy(buf[0..], self.data[0..]);
        return buf;
    }

    pub fn decode(data: []u8, _: chunk.DecoderContext, _: Allocator) !@This() {
        return SimpleChunkData{ .data = data };
    }
};
