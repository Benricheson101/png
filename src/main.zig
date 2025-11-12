const std = @import("std");
const colorpng = @import("colorpng");

const chunk = colorpng.chunk;
const ColorType = colorpng.chunk.ColorType;
const Chunk = colorpng.chunk.Chunk;
const IHDR = colorpng.chunk.IHDR;
const Color = colorpng.chunk.Color;

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var hdr = Chunk{ .IHDR = .{ .data = .{
        .width = 1_024,
        .height = 1_024,
        .bit_depth = 1,
        .color_type = ColorType.Indexed,
        .compression_method = 0,
        .filter_method = 0,
        .interlace_method = 0,
    } } };

    var colors = [_]Color{
        .{ .r = 0x9c, .g = 0x9c, .b = 0xfc },
    };

    var plte = Chunk{ .PLTE = .{ .data = .{ .palette = &colors } } };

    var end = Chunk{ .IEND = .{ .data = .{} } };

    var image_data: [1024 * 1025]u8 = undefined;
    @memset(image_data[0..], 0);

    var dat = Chunk{ .IDAT = .{ .data = .{ .image_data = image_data[0..] } } };

    const hdr_data = try hdr.IHDR.encode(allocator);
    const plte_data = try plte.PLTE.encode(allocator);
    const dat_data = try dat.IDAT.encode(allocator);
    const end_data = try end.IEND.encode(allocator);

    defer allocator.free(hdr_data);
    defer allocator.free(plte_data);
    defer allocator.free(dat_data);
    defer allocator.free(end_data);

    var s = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };

    const data = [_][]u8{
        s[0..],
        hdr_data,
        plte_data,
        dat_data,
        end_data,
    };

    var len: usize = 0;
    for (data) |d| {
        len += d.len;
    }

    var image: []u8 = try allocator.alloc(u8, len);
    defer allocator.free(image);

    var start: usize = 0;
    for (data) |d| {
        @memcpy(image[start .. start + d.len], d[0..]);
        start += d.len;
    }

    std.debug.print("image size: {d}\n", .{len});

    try std.fs.cwd().writeFile(.{
        .data = image[0..],
        .sub_path = "output_image.png",
        .flags = .{},
    });
}

// 0000000d4948445200001f1c000003ac08060000006421e671
