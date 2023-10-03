const std = @import("std");
const debug = @import("./debug.zig");
const chunk = @import("./chunk.zig");
const vm = @import("./vm.zig");
const Chunk = chunk.Chunk;
const Op_Code = chunk.Op_Code;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const ally = gpa.allocator();
    var ch = chunk.init(ally);
    defer chunk.deinit(ch);

    var v = vm.init();
    defer vm.deinit(&v);

    var constant_id = try chunk.add_constant(&ch, 1.2);
    try chunk.write(&ch, .{ .constant = constant_id }, 123);

    // constant = addConstant(&chunk, 3.4);
    // writeChunk(&chunk, OP_CONSTANT, 123);
    // writeChunk(&chunk, constant, 123);

    // writeChunk(&chunk, OP_ADD, 123);

    // constant = addConstant(&chunk, 5.6);
    // writeChunk(&chunk, OP_CONSTANT, 123);
    // writeChunk(&chunk, constant, 123);

    // writeChunk(&chunk, OP_DIVIDE, 123);

    constant_id = try chunk.add_constant(&ch, 3.4);
    try chunk.write(&ch, .{ .constant = constant_id }, 123);

    try chunk.write(&ch, .add, 123);

    constant_id = try chunk.add_constant(&ch, 5.6);
    try chunk.write(&ch, .{ .constant = constant_id }, 123);

    try chunk.write(&ch, .divide, 123);

    try chunk.write(&ch, .negate, 123);
    try chunk.write(&ch, .return_, 123);

    try vm.interpret(&v, ch);

    // debug.disassemble_chunk(ch, "test chunk");
}
