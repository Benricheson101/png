const std = @import("std");
const chunk = @import("../chunk.zig");

const Allocator = std.mem.Allocator;
const Chunk = chunk.Chunk;
const expectEqualSlices = std.testing.expectEqualSlices;

pub const TEXTData = struct {
    keyword: []const u8,
    str: []const u8,

    pub fn encode(self: *const TEXTData, allocator: Allocator) ![]u8 {
        const len = self.keyword.len + self.str.len + 1;
        var buf = try allocator.alloc(u8, len);
        @memset(buf[0..], 0);
        @memcpy(buf[0..self.keyword.len], self.keyword[0..]);
        @memcpy(buf[self.keyword.len + 1 .. len], self.str[0..self.str.len]);
        return buf;
    }

    pub fn decode(data: []u8, _: chunk.DecoderContext, _: Allocator) !@This() {
        var keyword_len: usize = 0;
        while (data[keyword_len] != 0) : (keyword_len += 1) {}

        return TEXTData{
            .keyword = data[0..keyword_len],
            .str = data[keyword_len + 1 ..],
        };
    }
};

test "tEXt encode" {
    var text = Chunk.init(.{
        .tEXt = .{ //
            .keyword = "hi",
            .str = "hello",
        },
    });

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

    const encoded_data = try text.encode(gpa);
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

    const text_chunk = try Chunk.decode(&data, .{}, gpa);

    try expectEqualSlices(u8, &[_]u8{ 'h', 'i' }, text_chunk.data.tEXt.keyword);
    try expectEqualSlices(u8, &[_]u8{ 'h', 'e', 'l', 'l', 'o' }, text_chunk.data.tEXt.str);
}
