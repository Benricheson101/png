const std = @import("std");
const chunk = @import("../chunk.zig");

const Allocator = std.mem.Allocator;
const Chunk = chunk.Chunk;
const PNGChunk = chunk.PNGChunk;
const expectEqualSlices = std.testing.expectEqualSlices;

const c = @cImport({
    @cInclude("zlib.h");
});

pub const IDAT = PNGChunk(.{ 'I', 'D', 'A', 'T' }, IDATData);

pub const IDATData = struct {
    image_data: []const u8,

    pub fn encode(self: *const IDATData, allocator: Allocator) ![]u8 {
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

    pub fn decode(data: []u8, ctx: chunk.DecoderContext, allocator: Allocator) !@This() {
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
    const ctx = chunk.DecoderContext{
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

    const idat_chunk = try Chunk.decode(&data, ctx, gpa);
    defer gpa.free(idat_chunk.IDAT.data.image_data);

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

    try expectEqualSlices(u8, expected_data[0..], idat_chunk.IDAT.data.image_data[0..]);
}
