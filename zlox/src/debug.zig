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
        Op_Code.op_add.byte() => return simple_instruction("OP_ADD", offset),
        Op_Code.op_subtract.byte() => return simple_instruction("OP_SUBTRACT", offset),
        Op_Code.op_multiply.byte() => return simple_instruction("OP_MULTIPLY", offset),
        Op_Code.op_divide.byte() => return simple_instruction("OP_DIVIDE", offset),
        Op_Code.op_constant.byte() => return constant_instruction("OP_CONSTANT", chunk, offset),
        Op_Code.op_constant_long.byte() => return constant_long_instruction("OP_CONSTANT_LONG", chunk, offset),
        Op_Code.op_negate.byte() => return simple_instruction("OP_NEGATE", offset),
        Op_Code.op_return.byte() => return simple_instruction("OP_RETURN", offset),
        else => std.debug.print("Unknown opcode {d}\n", .{instruction}),
    }

    return offset + 1;
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
    value.print(chunk.constants.items[idx]);
    std.debug.print("'\n", .{});
}

fn simple_instruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}
