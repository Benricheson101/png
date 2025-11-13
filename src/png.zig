const std = @import("std");
const chunk = @import("chunk.zig");
const color = @import("./util/color.zig");

const Allocator = std.mem.Allocator;
const Chunk = chunk.Chunk;

const ChunkArray = std.ArrayList(Chunk);

pub const PNG_SIGNATURE = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };

fn sortChunks(chunks: []Chunk) void {
    std.mem.sort(Chunk, chunks[0..], {}, struct {
        fn sort(_: void, a: Chunk, b: Chunk) bool {
            return @intFromEnum(a) < @intFromEnum(b);
        }
    }.sort);
}

pub const PNG = struct {
    chunks: ChunkArray,
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: Allocator, header: chunk.ihdr.IHDRData) !PNG {
        var arena_allocator = std.heap.ArenaAllocator.init(allocator);
        const arena_alloc = arena_allocator.allocator();

        var chunks = try ChunkArray.initCapacity(arena_alloc, 3);

        try chunks.append(arena_alloc, Chunk{ .IHDR = .{ .data = header } });

        return PNG{
            .chunks = chunks,
            .allocator = allocator,
            .arena = arena_allocator,
        };
    }

    pub fn addChunk(self: *PNG, c: Chunk) !void {
        try self.chunks.append(self.arena.allocator(), c);

        if (c == .IHDR) {
            _ = self.chunks.swapRemove(0);
        }
    }

    pub fn encode(self: *PNG) ![]u8 {
        const arena_alloc = self.arena.allocator();

        var chunks = try self.allocator.alloc([]u8, self.chunks.items.len + 1);
        defer self.allocator.free(chunks);

        sortChunks(self.chunks.items);

        var image_size: usize = 8 + 12;
        var chunks_added: usize = 0;
        lop: for (self.chunks.items, 0..) |c, i| {
            const buf: []u8 = switch (c) {
                .IEND => |_| break :lop,
                inline else => |v| try v.encode(arena_alloc),
            };

            chunks[i] = buf;
            chunks_added += 1;
            image_size += buf.len;
        }

        const iend = Chunk{ .IEND = .{ .data = .{} } };
        const iend_data = try iend.IEND.encode(arena_alloc);
        chunks[chunks_added] = iend_data;
        chunks_added += 1;

        var buf: []u8 = try arena_alloc.alloc(u8, image_size);
        @memcpy(buf[0..8], PNG_SIGNATURE[0..]);

        var offset: usize = 8;
        for (0..chunks_added) |i| {
            const c = chunks[i];
            @memcpy(buf[offset .. offset + c.len], c[0..]);
            offset += c.len;
        }

        return buf;
    }

    fn readNextChunk(buf: []u8) ![]u8 {
        const len = std.mem.readInt(u32, buf[0..4], .big);
        return buf[0 .. len + 12];
    }

    pub fn decode(allocator: Allocator, buf: []u8) !PNG {
        const MINIMUM_LENGTH: usize = PNG_SIGNATURE.len + 25 + 12; // magic numbers + ihdr + iend
        if (buf.len < MINIMUM_LENGTH) {
            return error.InvalidImage;
        }

        const sig = buf[0..PNG_SIGNATURE.len];
        if (!std.mem.eql(u8, sig, &PNG_SIGNATURE)) {
            return error.NotPNG;
        }

        var png = try PNG.init(allocator, .{ .width = 0, .height = 0 });

        var cursor = PNG_SIGNATURE.len;
        var ctx: chunk.DecoderContext = .{};

        while (cursor < buf.len) {
            const c = try readNextChunk(buf[cursor..]);
            cursor += c.len;
            const ch = Chunk.decode(c, ctx, png.arena.allocator()) catch continue;

            if (ch == .IHDR) {
                ctx.header = ch.IHDR.data;
            }

            // std.debug.print("decoded chunk {any}\n", .{ch});

            try png.addChunk(ch);
        }

        return png;
    }

    pub fn deinit(self: *PNG) void {
        self.arena.deinit();
    }
};

test "encode empty png" {
    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    var png = try PNG.init(gpa, .{
        .width = 16,
        .height = 16,
    });
    defer png.deinit();

    try png.addChunk(Chunk{
        .IEND = .init(.{}),
    });

    const data = try png.encode();

    const ihdr_chunk = [_]u8{
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

    const iend_chunk = [_]u8{
        0, 0, 0, 0, // length
        'I', 'E', 'N', 'D', // type
        174, 66, 96, 130, // crc32
    };

    const expected_data = PNG_SIGNATURE ++ ihdr_chunk ++ iend_chunk;

    try std.testing.expectEqualSlices(u8, expected_data[0..], data[0..]);
}

test "only one IEND chunk" {
    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    var png = try PNG.init(gpa, .{
        .width = 16,
        .height = 16,
    });
    defer png.deinit();

    const data = try png.encode();

    const ihdr_chunk = [_]u8{
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

    const iend_chunk = [_]u8{
        0, 0, 0, 0, // length
        'I', 'E', 'N', 'D', // type
        174, 66, 96, 130, // crc32
    };

    const expected_data = PNG_SIGNATURE ++ ihdr_chunk ++ iend_chunk;

    try std.testing.expectEqualSlices(u8, expected_data[0..], data[0..]);
}

test "chunk sort" {
    var chunks = [_]Chunk{
        .{ .IHDR = .init(.{ .width = 32, .height = 32 }) },
        .{ .IEND = .init(.{}) },
        .{ .IDAT = .init(.{ .image_data = &[0]u8{} }) },
        .{ .PLTE = .init(.{ .palette = &[0]color.Color{} }) },
    };

    sortChunks(&chunks);

    const expected_order = [_]chunk.ChunkType{ .IHDR, .PLTE, .IDAT, .IEND };

    for (chunks, 0..) |c, i| {
        const tag: chunk.ChunkType = std.meta.activeTag(c);
        try std.testing.expectEqual(tag, expected_order[i]);
    }
}

test "decode png" {
    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    var png = try PNG.init(gpa, .{ .width = 9, .height = 9 });
    defer png.deinit();

    try png.addChunk(Chunk{
        .PLTE = .init(.{
            .palette = &[_]color.Color{
                .{ .r = 0xeb, .g = 0x4f, .b = 0x34 }, // 0: red-orange
                .{ .r = 0x00, .g = 0x00, .b = 0x00 }, // 1: black
            },
        }),
    });

    try png.addChunk(Chunk{
        .IDAT = .init(.{ //
            .image_data = &[_]u8{
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 1, 1, 0, 0, 1, 1, 1, 0,
                0, 0, 1, 1, 1, 0, 0, 0, 1, 0,
                0, 0, 1, 1, 1, 0, 0, 0, 1, 0,
                0, 0, 0, 0, 0, 0, 1, 1, 1, 0,
                0, 0, 1, 1, 0, 0, 0, 0, 1, 0,
                0, 0, 1, 1, 1, 0, 0, 0, 1, 0,
                0, 0, 1, 1, 1, 0, 1, 1, 1, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            },
        }),
    });

    try png.addChunk(Chunk{
        .tEXt = .init(.{ //
            .keyword = "Title",
            .str = "rawr",
        }),
    });

    try png.addChunk(Chunk{
        .tEXt = .init(.{ //
            .keyword = "Author",
            .str = "Ben",
        }),
    });

    try png.addChunk(Chunk{
        .tEXt = .init(.{ //
            .keyword = "Software",
            .str = "colorpng",
        }),
    });

    try png.addChunk(.{
        .iTXt = .init(.{
            .keyword = "Description",
            .language_tag = "en",
            .translated_keyword = "Description",
            .text = ":3c",
        }),
    });

    try png.addChunk(.{
        .iTXt = .init(.{
            .keyword = "Description",
            .language_tag = "fr",
            .translated_keyword = "oui oui",
            .text = "baguette",
        }),
    });

    const data = try png.encode();
    var decoded = try PNG.decode(gpa, data[0..]);
    defer decoded.deinit();

    const enc = try decoded.encode();

    try std.testing.expectEqualSlices(u8, data, enc);
}
