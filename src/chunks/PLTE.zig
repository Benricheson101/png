const std = @import("std");
const chunk = @import("../chunk.zig");
const Color = @import("../util/color.zig").Color;

const Allocator = std.mem.Allocator;
const Chunk = chunk.Chunk;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqual = std.testing.expectEqual;

pub const PLTEData = struct {
    palette: []const Color,

    pub fn encode(self: *const PLTEData, allocator: Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, self.palette.len * 3);
        @memset(buf[0..], 0);

        for (self.palette, 0..) |color, i| {
            const bytes: u24 = @bitCast(color);
            std.mem.writePackedInt(u24, buf[(i * 3) .. (i * 3) + 3], 0, bytes, .big);
        }

        return buf;
    }

    pub fn decode(data: []u8, _: chunk.DecoderContext, allocator: Allocator) !@This() {
        if (data.len % 3 != 0) {
            return error.BadChunkData;
        }

        const n_colors = data.len / 3;
        var colors = try allocator.alloc(Color, n_colors);

        var n: usize = 0;
        var i: usize = 0;
        while (i < n_colors) : (n += 3) {
            const byt = data[n .. n + 3];
            const color = Color.fromBytes(byt);
            colors[i] = color;
            i += 1;
        }

        return PLTEData{
            .palette = colors,
        };
    }
};

test "PLTE encode" {
    var plte = Chunk.init(.{
        .PLTE = .{
            .palette = &[_]Color{
                .{ .r = 0xff, .g = 0x00, .b = 0xaa },
                .{ .r = 0xcc, .g = 0xee, .b = 0x09 },
            },
        },
    });

    const data = [_]u8{
        0, 0, 0, 6, // length
        'P', 'L', 'T', 'E', // type
        0xff, 0, 0xaa, // palette 0
        0xcc, 0xee, 0x09, // palette 0
        66, 225, 226, 128, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const encoded_data = try plte.encode(gpa);
    defer gpa.free(encoded_data);

    try expectEqualSlices(u8, data[0..], encoded_data[0..]);
}

test "PLTE decode" {
    var data = [_]u8{
        0, 0, 0, 6, // length
        'P', 'L', 'T', 'E', // type
        0xff, 0, 0xaa, // palette 0
        0xcc, 0xee, 0x09, // palette 1
        66, 225, 226, 128, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const plte_chunk = try Chunk.decode(&data, .{}, gpa);
    const palette = plte_chunk.data.PLTE.palette;
    defer gpa.free(palette);

    try expectEqual(Color{ .r = 0xff, .g = 0x00, .b = 0xaa }, palette[0]);
    try expectEqual(Color{ .r = 0xcc, .g = 0xee, .b = 0x09 }, palette[1]);
}
