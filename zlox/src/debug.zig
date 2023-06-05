const std = @import("std");
const Chunk = @import("./chunk.zig").Chunk;
const Op_Code = @import("./chunk.zig").Op_Code;
const value = @import("./value.zig");

pub fn disassemble_chunk(chunk: Chunk, name: []const u8) !void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = try disassemble_instruction(chunk, offset);
    }
}

pub fn disassemble_instruction(chunk: Chunk, offset: usize) !usize {
    std.debug.print("{d:0<4} ", .{offset});

    if (0 < offset and chunk.lines.items[offset] == chunk.lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:4} ", .{chunk.lines.items[offset]});
    }

    const instruction = chunk.code.items[offset];

    switch (instruction) {
        Op_Code.op_nil.byte() => return simple_instruction("OP_NIL", offset),
        Op_Code.op_true.byte() => return simple_instruction("OP_TRUE", offset),
        Op_Code.op_false.byte() => return simple_instruction("OP_FALSE", offset),
        Op_Code.op_pop.byte() => return simple_instruction("OP_POP", offset),
        Op_Code.op_define_global.byte() => return constant_instruction("OP_DEFINE_GLOBAL", chunk, offset),
        Op_Code.op_get_global.byte() => return constant_instruction("OP_GET_GLOBAL", chunk, offset),
        Op_Code.op_get_local.byte() => return byte_instruction("OP_GET_LOCAL", chunk, offset),
        Op_Code.op_set_global.byte() => return constant_instruction("OP_SET_GLOBAL", chunk, offset),
        Op_Code.op_set_local.byte() => return byte_instruction("OP_SET_LOCAL", chunk, offset),
        Op_Code.op_equal.byte() => return simple_instruction("OP_EQUAL", offset),
        Op_Code.op_greater.byte() => return simple_instruction("OP_GREATER", offset),
        Op_Code.op_less.byte() => return simple_instruction("OP_LESS", offset),
        Op_Code.op_add.byte() => return simple_instruction("OP_ADD", offset),
        Op_Code.op_subtract.byte() => return simple_instruction("OP_SUBTRACT", offset),
        Op_Code.op_multiply.byte() => return simple_instruction("OP_MULTIPLY", offset),
        Op_Code.op_divide.byte() => return simple_instruction("OP_DIVIDE", offset),
        Op_Code.op_not.byte() => return simple_instruction("OP_NOT", offset),
        Op_Code.op_constant.byte() => return constant_instruction("OP_CONSTANT", chunk, offset),
        Op_Code.op_constant_long.byte() => return constant_long_instruction("OP_CONSTANT_LONG", chunk, offset),
        Op_Code.op_negate.byte() => return simple_instruction("OP_NEGATE", offset),
        Op_Code.op_print.byte() => return simple_instruction("OP_PRINT", offset),
        Op_Code.op_jump.byte() => return jump_instruction("OP_JUMP", 1, chunk, offset),
        Op_Code.op_jump_if_false.byte() => return jump_instruction("OP_JUMP_IF_FALSE", 1, chunk, offset),
        Op_Code.op_loop.byte() => return jump_instruction("OP_LOOP", -1, chunk, offset),
        Op_Code.op_return.byte() => return simple_instruction("OP_RETURN", offset),
        else => std.debug.print("Unknown opcode {d}\n", .{instruction}),
    }

    return offset + 1;
}

fn jump_instruction(name: []const u8, sign: isize, chunk: Chunk, offset: usize) usize {
    var jump = @intCast(isize, chunk.code.items[offset + 1]) << 8;
    jump |= chunk.code.items[offset + 2];
    std.debug.print("{s:<16} {d:4} -> {d}\n", .{ name, offset, @intCast(isize, offset) + 3 + sign * jump });
    return offset + 3;
}

fn byte_instruction(name: []const u8, chunk: Chunk, offset: usize) usize {
    const slot = chunk.code.items[offset + 1];
    std.debug.print("{s:<16} {d:4}\n", .{ name, slot });
    return offset + 2;
}

fn constant_long_instruction(name: []const u8, chunk: Chunk, offset: usize) usize {
    const idx_hi = @intCast(u16, chunk.code.items[offset + 1]);
    const idx_lo = @intCast(u16, chunk.code.items[offset + 2]);
    const constant_idx = (idx_hi << 8) | idx_lo;
    print_constant(name, chunk, constant_idx);

    return offset + 3;
}

fn constant_instruction(name: []const u8, chunk: Chunk, offset: usize) usize {
    const constant_idx = chunk.code.items[offset + 1];
    print_constant(name, chunk, constant_idx);

    return offset + 2;
}

fn print_constant(name: []const u8, chunk: Chunk, idx: usize) void {
    std.debug.print("{s:<16} {d:4} '", .{ name, idx });
    value.Value.print_unbuff(chunk.constants.items[idx]);
    std.debug.print("'\n", .{});
}

fn simple_instruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}
