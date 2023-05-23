const std = @import("std");
const Chunk = @import("./chunk.zig").Chunk;
const Op_Code = @import("./chunk.zig").Op_Code;
const debug = @import("./debug.zig");
const VM = @import("./vm.zig").VM;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var vm = VM.init(alloc);
    defer vm.deinit();

    var chunk = Chunk.init(alloc);
    defer chunk.deinit();

    try chunk.append_constant(1.2, 123);
    try chunk.append_constant(3.4, 123);

    try chunk.append_byte(Op_Code.op_add.byte(), 123);

    try chunk.append_constant(5.6, 123);

    try chunk.append_byte(Op_Code.op_divide.byte(), 123);
    try chunk.append_byte(Op_Code.op_negate.byte(), 123);

    try chunk.append_byte(Op_Code.op_return.byte(), 123);

    try vm.interpret(chunk);

    // try debug.disassemble_chunk(chunk, "test chunk");
}
