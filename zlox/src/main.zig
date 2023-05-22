const std = @import("std");
const Chunk = @import("./chunk.zig").Chunk;
const Op_Code = @import("./chunk.zig").Op_Code;
const debug = @import("./debug.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();
    var chunk = Chunk.init(alloc);
    defer chunk.deinit();

    try chunk.append_constant(1.23, 123);
    try chunk.append_byte(Op_Code.op_return.byte(), 123);

    try debug.disassemble_chunk(chunk, "test chunk");
}
