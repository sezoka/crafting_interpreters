const std = @import("std");
const debug = @import("debug.zig");
const chunk = @import("chunk.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var c = chunk.init(alloc);
    defer chunk.deinit(&c);

    const constant = try chunk.add_constant(&c, 1.2);
    try chunk.append_byte_code(&c, .Constant, 123);
    try chunk.append_byte(&c, constant, 123);

    try chunk.append_byte_code(&c, .Return, 123);

    debug.disassemble_chunk(c, "test chunk");
}
