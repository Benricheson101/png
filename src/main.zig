const std = @import("std");
const colorpng = @import("colorpng");

const Chunk = colorpng.chunk.Chunk;
const Color = colorpng.chunk.Color;
const PNG = colorpng.png.PNG;

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var png = try PNG.init(allocator, .{ .width = 32, .height = 32 });
    defer png.deinit();

    try png.addChunk(Chunk{
        .PLTE = .{ .data = .{ .palette = &[_]Color{.{ .r = 0x10, .g = 0xab, .b = 0xef }} } },
    });

    try png.addChunk(Chunk{ .IDAT = .{ .data = .{
        .image_data = &[_]u8{0} ** (32 * 33),
    } } });

    const encoded = try png.encode();
    defer allocator.free(encoded);

    try std.fs.cwd().writeFile(.{
        .data = encoded[0..],
        .sub_path = "output_image_test.png",
        .flags = .{},
    });
}
