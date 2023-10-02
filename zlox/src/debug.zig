const std = @import("std");
const chunk = @import("./chunk.zig");
const value = @import("./value.zig");
const io = @import("./io.zig");
const Chunk = chunk.Chunk;
const Op_Code = chunk.Op_Code;

pub fn disassemble_chunk(ch: Chunk, name: []const u8) void {
    io.print("== {s} ==\n", .{name});
    var offset: usize = 0;
    while (offset < ch.code.items.len) {
        offset = disassemble_instruction(ch, offset);
    }
}

fn disassemble_instruction(ch: Chunk, offset: usize) usize {
    io.print("{d:0>4} ", .{offset});

    if (0 < offset and ch.lines.items[offset] == ch.lines.items[offset - 1]) {
        io.print("   | ", .{});
    } else {
        io.print("{d:>4} ", .{ch.lines.items[offset]});
    }

    const instr = ch.code.items[offset];
    return switch (instr) {
        .return_ => simple_instruction("OP_RETURN", offset),
        .constant => |id| constant_instruction("OP_CONSTANT", ch, id, offset),
    };
}

pub fn constant_instruction(name: []const u8, ch: Chunk, constant_id: usize, offset: usize) usize {
    io.print("{s:<16} {d:>4} '", .{ name, constant_id });
    value.print(ch.constants.items[constant_id]);
    io.print("'\n", .{});
    return offset + 1;
}

pub fn simple_instruction(name: []const u8, offset: usize) usize {
    io.print("{s}\n", .{name});
    return offset + 1;
}
