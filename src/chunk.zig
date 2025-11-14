const std = @import("std");

const Allocator = std.mem.Allocator;
const Crc32 = std.hash.Crc32;

// order is important here!
pub const Chunk = makeChunks(.{
    .IHDR = .{ .data = @import("./chunks/IHDR.zig").IHDRData },
    .tEXt = .{ .data = @import("./chunks/tEXt.zig").TEXTData },
    .iTXt = .{ .data = @import("./chunks/iTXt.zig").ITXTData },
    .tIME = .{ .data = @import("./chunks/tIME.zig").tIMEData },
    .sRGB = .{ .data = @import("./chunks/sRGB.zig").SRGBData },
    .PLTE = .{ .data = @import("./chunks/PLTE.zig").PLTEData },
    .tRNS = .{ .data = @import("./chunks/tRNS.zig").tRNSData },
    .bKGD = .{ .data = @import("./chunks/bKGD.zig").bKGDData },
    .IDAT = .{ .data = @import("./chunks/IDAT.zig").IDATData },
    .IEND = .{ .data = @import("./chunks/IEND.zig").IENDData },
});

pub const DecoderContext = struct {
    header: ?@FieldType(Chunk.ChunkData, "IHDR") = null,
};

// TODO: can I somehow make a "CUSTOM" type in the enum that takes any type?

/// A generic PNG chunk
///
/// 4 bytes: data length
/// 4 bytes: chunk type
/// ? bytes: data
/// 4 bytes: crc32
fn makeChunks(comptime chunks: anytype) type {
    const fields = @typeInfo(@TypeOf(chunks)).@"struct".fields;

    var enum_fields: [fields.len]std.builtin.Type.EnumField = undefined;
    var chunk_data_union_fields: [fields.len]std.builtin.Type.UnionField = undefined;

    inline for (fields, 0..) |f, i| {
        var name: [f.name.len:0]u8 = undefined;
        @memcpy(name[0..], f.name[0..]);

        enum_fields[i] = .{
            .name = &name,
            .value = i,
        };

        const field_value = @field(chunks, f.name);
        const Data = field_value.data;

        chunk_data_union_fields[i] = .{
            .name = &name,
            .type = Data,
            .alignment = @alignOf(Data),
        };
    }

    const chunk_type_enum = @Type(.{ //
        .@"enum" = .{
            .tag_type = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @ceil(@log2(@as(f32, fields.len))) } }),
            .decls = &.{},
            .is_exhaustive = true,
            .fields = &enum_fields,
        },
    });

    const chunk_data = @Type(.{ //
        .@"union" = .{
            .tag_type = chunk_type_enum,
            .fields = &chunk_data_union_fields,
            .decls = &.{},
            .layout = .auto,
        },
    });

    const chunk_type_map = std.StaticStringMap(chunk_type_enum).initComptime(blk: {
        var field_name_map: [fields.len]struct { []const u8, chunk_type_enum } = undefined;
        inline for (fields, 0..) |f, i| {
            const name = f.name;
            field_name_map[i] = .{ name, @enumFromInt(i) };
        }

        break :blk field_name_map;
    });

    return struct {
        const BASE_CHUNK_SIZE: usize = 12;

        const Self = @This();

        pub const ChunkType = chunk_type_enum;
        pub const ChunkData = chunk_data;

        data: ChunkData,

        pub fn init(data: ChunkData) Self {
            return Self{
                .data = data,
            };
        }

        pub fn encode(self: *const Self, allocator: Allocator) ![]u8 {
            const data = switch (self.data) {
                inline else => |v| try v.encode(allocator),
            };
            defer allocator.free(data);

            const buf = try allocator.alloc(u8, data.len + BASE_CHUNK_SIZE);
            @memset(buf[0..], 0);

            std.mem.writeInt(u32, buf[0..4], @intCast(data.len), .big);
            const chunk_typ = @tagName(self.data);
            @memcpy(buf[4..8], chunk_typ[0..4]);

            @memmove(buf[8 .. buf.len - 4], data[0..]);

            const crc = Crc32.hash(buf[4 .. buf.len - 4]);
            std.mem.writePackedInt(u32, buf[buf.len - 4 ..], 0, crc, .big);

            return buf;
        }

        pub fn decode(data: []u8, ctx: DecoderContext, allocator: Allocator) !Self {
            const len_bytes = data[0..4];
            const len = std.mem.readInt(u32, len_bytes, .big);

            const chunk_type = chunk_type_map.get(data[4..8]) orelse return error.UnknownChunk;

            const raw_chunk_data = data[8 .. len + 8];
            const crc_bytes = data[len + 8 .. len + 12];
            const crc = std.mem.readPackedInt(u32, crc_bytes, 0, .big);

            const actual_crc = Crc32.hash(data[4 .. len + 8]);
            if (crc != actual_crc) {
                return error.BadChecksum;
            }

            inline for (@typeInfo(ChunkData).@"union".fields) |f| {
                const tag = @field(ChunkType, f.name);
                if (chunk_type == tag) {
                    return Self{
                        .data = @unionInit(ChunkData, f.name, try .decode(raw_chunk_data, ctx, allocator)),
                    };
                }
            }

            unreachable;
        }
    };
}
