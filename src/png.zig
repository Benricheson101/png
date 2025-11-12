const std = @import("std");
const Allocator = std.mem.Allocator;

const chunk = @import("chunk.zig");
const Chunk = chunk.Chunk;

const ChunkArray = std.ArrayList(Chunk);

pub const PNG_SIGNATURE = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };

pub const PNG = struct {
    chunks: ChunkArray,
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: Allocator, header: chunk.IHDRData) !PNG {
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
    }

    pub fn encode(self: *PNG) ![]u8 {
        const arena_alloc = self.arena.allocator();

        var chunks = try self.allocator.alloc([]u8, self.chunks.items.len + 1);
        defer self.allocator.free(chunks);

        var image_size: usize = 8 + 12;

        for (self.chunks.items, 0..) |c, i| {
            const buf = switch (c) {
                .IHDR => |v| try v.encode(arena_alloc),
                .PLTE => |v| try v.encode(arena_alloc),
                .IEND => |v| try v.encode(arena_alloc),
                .IDAT => |v| try v.encode(arena_alloc),
            };

            chunks[i] = buf;
            image_size += buf.len;
        }

        const iend = Chunk{ .IEND = .{ .data = .{} } };
        const iend_data = try iend.IEND.encode(arena_alloc);
        chunks[chunks.len - 1] = iend_data;

        var buf: []u8 = try arena_alloc.alloc(u8, image_size);
        @memcpy(buf[0..8], PNG_SIGNATURE[0..]);

        var offset: usize = 8;
        for (chunks) |c| {
            @memcpy(buf[offset .. offset + c.len], c[0..]);
            offset += c.len;
        }

        return buf;
    }

    pub fn deinit(self: *PNG) void {
        self.arena.deinit();
    }
};

test "empty png" {
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
