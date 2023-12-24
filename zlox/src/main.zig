const std = @import("std");

const chunk = @import("chunk.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const ally = gpa.allocator();

    var ch = chunk.create(ally);
    defer chunk.deinit(ch);

    const constant = try chunk.add_constant(&ch, 1.2);

    try chunk.write(&ch, .Constant, 123);
    try chunk.write_byte(&ch, constant, 123);
    try chunk.write(&ch, .Return, 123);

    debug.disassemble_chunk(ch, "test chunk");
}
