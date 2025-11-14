const SimpleChunkData = @import("./simple.zig").SimpleChunkData;
const PNGChunk = @import("../chunk.zig").PNGChunk;

pub const bKGD = PNGChunk(.{ 'b', 'K', 'G', 'D' }, SimpleChunkData);
