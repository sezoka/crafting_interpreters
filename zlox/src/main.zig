const std = @import("std");
const debug = @import("./debug.zig");
const chunk = @import("./chunk.zig");
const Chunk = chunk.Chunk;
const Op_Code = chunk.Op_Code;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const ally = gpa.allocator();
    var ch = chunk.init(ally);
    defer chunk.deinit(ch);

    const constant_id = try chunk.add_constant(&ch, 1.2);
    try chunk.write(&ch, .{ .constant = constant_id }, 123);
    try chunk.write(&ch, .return_, 123);

    debug.disassemble_chunk(ch, "test chunk");
}
