const std = @import("std");
const chunk = @import("../chunk.zig");

const Allocator = std.mem.Allocator;
const Chunk = chunk.Chunk;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqual = std.testing.expectEqual;

pub const tIMEData = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,

    pub fn encode(self: *const tIMEData, allocator: Allocator) ![]u8 {
        var buf = try allocator.alloc(u8, 7);

        std.mem.writeInt(u16, buf[0..2], self.year, .big);
        buf[2] = self.month;
        buf[3] = self.day;
        buf[4] = self.hour;
        buf[5] = self.minute;
        buf[6] = self.second;

        return buf;
    }

    pub fn decode(data: []u8, _: chunk.DecoderContext, _: Allocator) !@This() {
        return tIMEData{
            .year = std.mem.readInt(u16, data[0..2], .big),
            .month = data[2],
            .day = data[3],
            .hour = data[4],
            .minute = data[5],
            .second = data[6],
        };
    }
};

test "tIME encode" {
    var time = Chunk.init(.{
        .tIME = .{
            .year = 2025,
            .month = 11,
            .day = 13,
            .hour = 20,
            .minute = 28,
            .second = 31,
        },
    });

    const data = [_]u8{
        0, 0, 0, 7, // length
        't', 'I', 'M', 'E', // type
        7, 233, // year
        11, // month
        13, // day
        20, // hour
        28, // minue
        31, // second
        8,
        117,
        82,
        34, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const encoded_data = try time.encode(gpa);
    defer gpa.free(encoded_data);

    try expectEqualSlices(u8, data[0..], encoded_data[0..]);
}

test "tIME decode" {
    var data = [_]u8{
        0, 0, 0, 7, // length
        't', 'I', 'M', 'E', // type
        7, 233, // year
        11, // month
        13, // day
        20, // hour
        28, // minue
        31, // second
        8,
        117,
        82,
        34, // crc32
    };

    var dbg_alloc = std.heap.DebugAllocator(.{}){};
    defer _ = dbg_alloc.deinit();
    const gpa = dbg_alloc.allocator();

    const time_chunk = try Chunk.decode(&data, .{}, gpa);
    const time_data = time_chunk.data.tIME;

    try expectEqual(time_data.year, 2025);
    try expectEqual(time_data.month, 11);
    try expectEqual(time_data.day, 13);
    try expectEqual(time_data.hour, 20);
    try expectEqual(time_data.minute, 28);
    try expectEqual(time_data.second, 31);
}
