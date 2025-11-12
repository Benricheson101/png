const std = @import("std");
const colorpng = @import("colorpng");

const Chunk = colorpng.chunk.Chunk;
const Color = colorpng.chunk.Color;
const PNG = colorpng.png.PNG;

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var png = try PNG.init(allocator, .{ .width = 9, .height = 9 });
    defer png.deinit();

    try png.addChunk(Chunk{
        .PLTE = .{
            .data = .{
                .palette = &[_]Color{
                    .{ .r = 0xeb, .g = 0x4f, .b = 0x34 }, // 0: red-orange
                    .{ .r = 0x00, .g = 0x00, .b = 0x00 }, // 1: black
                },
            },
        },
    });

    try png.addChunk(Chunk{
        .IDAT = .{
            .data = .{ // :3
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
            },
        },
    });

    const encoded = try png.encode();

    try std.fs.cwd().writeFile(.{
        .data = encoded[0..],
        .sub_path = "output_image_test.png",
        .flags = .{},
    });
}
