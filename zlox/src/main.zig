const std = @import("std");

const vm = @import("vm.zig");
const chunk = @import("chunk.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const ally = gpa.allocator();

    var vm_inst = vm.create(ally);
    defer vm.deinit(vm_inst);

    var ch = chunk.create(ally);
    defer chunk.deinit(ch);

    {
        var constant_idx = try chunk.add_constant(&ch, 1.2);
        try chunk.write(&ch, .Constant, 123);
        try chunk.write_byte(&ch, constant_idx, 123);

        constant_idx = try chunk.add_constant(&ch, 3.4);
        try chunk.write(&ch, .Constant, 123);
        try chunk.write_byte(&ch, constant_idx, 123);

        try chunk.write(&ch, .Add, 123);

        constant_idx = try chunk.add_constant(&ch, 5.6);
        try chunk.write(&ch, .Constant, 123);
        try chunk.write_byte(&ch, constant_idx, 123);

        try chunk.write(&ch, .Divide, 123);

        try chunk.write(&ch, .Negate, 123);
        try chunk.write(&ch, .Return, 123);
    }

    try vm.interpret(&vm_inst, &ch);

    debug.disassemble_chunk(ch, "test chunk");
}
