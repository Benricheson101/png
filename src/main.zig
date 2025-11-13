const std = @import("std");
const colorpng = @import("colorpng");

const Chunk = colorpng.chunk.Chunk;
const Color = colorpng.chunk.Color;
const PNG = colorpng.png.PNG;

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var png = try PNG.init(allocator, .{
        .width = 9,
        .height = 9,
        .bit_depth = 8,
        .color_type = .indexed,
        .compression_method = 0,
        .filter_method = 0,
        .interlace_method = 0,
    });
    defer png.deinit();

    try png.addChunk(.{
        .PLTE = .init(.{
            .palette = &[_]Color{
                .{ .r = 0xeb, .g = 0x4f, .b = 0x34 }, // 0: red-orange
                .{ .r = 0x00, .g = 0x00, .b = 0x00 }, // 1: black
            },
        }),
    });

    try png.addChunk(.{
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

    try png.addChunk(.{
        .tEXt = .init(.{ //
            .keyword = "Title",
            .str = "rawr",
        }),
    });

    try png.addChunk(.{
        .tEXt = .init(.{ //
            .keyword = "Author",
            .str = "Ben",
        }),
    });

    try png.addChunk(.{
        .tEXt = .init(.{ //
            .keyword = "Software",
            .str = "coputer",
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

    // const encoded = try png.encode();

    // try std.fs.cwd().writeFile(.{
    //     .data = encoded[0..],
    //     .sub_path = "output_image_test.png",
    //     .flags = .{},
    // });

    // _ = try PNG.decode(allocator, encoded);
}
