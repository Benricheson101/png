const std = @import("std");

pub const Color = packed struct(u24) {
    b: u8,
    g: u8,
    r: u8,

    pub fn toBytes(self: Color) [3]u8 {
        const color: u24 = @bitCast(self);
        var buf: [3]u8 = undefined;
        std.mem.writeInt(u24, buf[0..3], color, .big);
        return buf;
    }

    pub fn fromBytes(buf: []const u8) Color {
        const nr = std.mem.readInt(u24, buf[0..3], .big);
        return @bitCast(nr);
    }
};

test "color packed struct" {
    const color = Color{ .r = 0x9c, .g = 0x9c, .b = 0xfc };

    const as_int: u24 = @bitCast(color);
    try std.testing.expectEqual(as_int, 0x9c9cfc);

    const new_color: Color = @bitCast(as_int);
    try std.testing.expectEqual(new_color, Color{ .r = 0x9c, .g = 0x9c, .b = 0xfc });
}

test "color toBytes" {
    const color = Color{ .r = 0x9c, .g = 0x9c, .b = 0xfc };
    const bytes = color.toBytes();

    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x9c, 0x9c, 0xfc }, bytes[0..]);
}

test "color fromBytes" {
    const color_code = [3]u8{ 0x9c, 0x9c, 0xfc };
    const color = Color.fromBytes(color_code[0..]);

    try std.testing.expectEqual(Color{ .r = 0x9c, .g = 0x9c, .b = 0xfc }, color);
}
