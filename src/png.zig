const std = @import("std");
const Allocator = std.mem.Allocator;

const chunk = @import("chunk.zig");
const Chunk = chunk.Chunk;

const ChunkArray = std.ArrayList(Chunk);

pub const PNG_SIGNATURE = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };

pub const PNG = struct {
    chunks: ChunkArray,
    allocator: Allocator,

    pub fn init(allocator: Allocator, header: chunk.IHDRData) !PNG {
        var chunks = try ChunkArray.initCapacity(allocator, 3);

        try chunks.append(allocator, Chunk{ .IHDR = .{ .data = header } });

        return PNG{
            .chunks = chunks,
            .allocator = allocator,
        };
    }

    pub fn addChunk(self: *PNG, c: Chunk) !void {
        try self.chunks.append(self.allocator, c);
    }

    pub fn encode(self: *PNG) ![]u8 {
        // var arr: [self.chunks.items][]u8 = undefined;
        var chunks = try self.allocator.alloc([]u8, self.chunks.items.len + 1);
        defer self.allocator.free(chunks);

        var image_size: usize = 8 + 12;

        for (self.chunks.items, 0..) |c, i| {
            const buf = switch (c) {
                .IHDR => |v| try v.encode(self.allocator),
                .PLTE => |v| try v.encode(self.allocator),
                .IEND => |v| try v.encode(self.allocator),
                .IDAT => |v| try v.encode(self.allocator),
            };

            chunks[i] = buf;
            image_size += buf.len;
        }

        const iend = Chunk{ .IEND = .{ .data = .{} } };
        const iend_data = try iend.IEND.encode(self.allocator);
        chunks[chunks.len - 1] = iend_data;

        var buf: []u8 = try self.allocator.alloc(u8, image_size);
        @memcpy(buf[0..8], PNG_SIGNATURE[0..]);

        var offset: usize = 8;
        for (chunks) |c| {
            @memcpy(buf[offset .. offset + c.len], c[0..]);
            offset += c.len;
        }

        return buf;
    }

    pub fn deinit(self: *PNG) void {
        self.chunks.deinit(self.allocator);
    }
};
