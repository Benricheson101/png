const std = @import("std");
const chunk = @import("../chunk.zig");

const Allocator = std.mem.Allocator;
const Chunk = chunk.Chunk;
const expectEqualSlices = std.testing.expectEqualSlices;

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

    pub fn encode(self: *const ITXTData, allocator: Allocator) ![]u8 {
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

    pub fn decode(data: []u8, _: chunk.DecoderContext, _: Allocator) !@This() {
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

test "iTXt encode" {
    var itxt = Chunk.init(.{
        .iTXt = .{ //
            .keyword = "hi",
            .compression_flag = 0,
            .compression_method = 0,
            .language_tag = "en-us",
            .translated_keyword = "hi",
            .text = "heyyy",
        },
    });

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

    const encoded_data = try itxt.encode(gpa);
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

    const itxt_chunk = try Chunk.decode(&data, .{}, gpa);

    try expectEqualSlices(u8, &[_]u8{ 'h', 'i' }, itxt_chunk.data.iTXt.keyword[0..]);
    try expectEqualSlices(u8, &[_]u8{ 'e', 'n', '-', 'u', 's' }, itxt_chunk.data.iTXt.language_tag[0..]);
    try expectEqualSlices(u8, &[_]u8{ 'h', 'i' }, itxt_chunk.data.iTXt.translated_keyword[0..]);
    try expectEqualSlices(u8, &[_]u8{ 'h', 'e', 'y', 'y', 'y' }, itxt_chunk.data.iTXt.text[0..]);
}
