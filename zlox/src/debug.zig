const std = @import("std");
const chunk = @import("./chunk.zig");
const value = @import("./value.zig");
const Chunk = chunk.Chunk;
const Op_Code = chunk.Op_Code;

pub const enabled = true;

pub fn disassemble_chunk(ch: Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});
    var offset: usize = 0;
    while (offset < ch.code.items.len) {
        offset = disassemble_instruction(ch, offset);
    }
}

pub fn disassemble_instruction(ch: Chunk, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset});

    if (0 < offset and ch.lines.items[offset] == ch.lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:>4} ", .{ch.lines.items[offset]});
    }

    const instr = ch.code.items[offset];
    return switch (instr) {
        .return_ => simple_instruction("OP_RETURN", offset),
        .constant => |id| constant_instruction("OP_CONSTANT", ch, id, offset),
        .negate => simple_instruction("OP_NEGATE", offset),
        .add => simple_instruction("OP_ADD", offset),
        .subtract => simple_instruction("OP_SUBTRACT", offset),
        .multiply => simple_instruction("OP_MULTIPLY", offset),
        .divide => simple_instruction("OP_DIVIDE", offset),
    };
}

pub fn constant_instruction(name: []const u8, ch: Chunk, constant_id: usize, offset: usize) usize {
    std.debug.print("{s:<16} {d:>4} '", .{ name, constant_id });
    value.print_debug(ch.constants.items[constant_id]);
    std.debug.print("'\n", .{});
    return offset + 1;
}

pub fn simple_instruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}
