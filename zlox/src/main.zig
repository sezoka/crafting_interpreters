const std = @import("std");
const debug = @import("debug.zig");
const chunk = @import("chunk.zig");
const vm = @import("vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var m = vm.init(alloc);
    defer vm.deinit(&m);

    var c = chunk.init(alloc);
    defer chunk.deinit(&c);

    var constant = try chunk.add_constant(&c, 1.2);
    try chunk.append_byte_code(&c, .Constant, 123);
    try chunk.append_byte(&c, constant, 123);

    constant = try chunk.add_constant(&c, 3.4);
    try chunk.append_byte_code(&c, .Constant, 123);
    try chunk.append_byte(&c, constant, 123);

    try chunk.append_byte_code(&c, .Add, 123);

    constant = try chunk.add_constant(&c, 5.6);
    try chunk.append_byte_code(&c, .Constant, 123);
    try chunk.append_byte(&c, constant, 123);

    try chunk.append_byte_code(&c, .Divide, 123);
    try chunk.append_byte_code(&c, .Negate, 123);

    try chunk.append_byte_code(&c, .Return, 123);

    debug.disassemble_chunk(c, "test chunk");

    try vm.interpret(&m, c);
}
