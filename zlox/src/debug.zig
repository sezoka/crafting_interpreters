const std = @import("std");
const value = @import("value.zig");
const chunk = @import("chunk.zig");
const Chunk = chunk.Chunk;
const Op_Code = chunk.Op_Code;

pub const IS_DEBUG = true;

pub fn disassemble_chunk(ch: Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < ch.code.items.len) {
        offset += disassemble_instr(ch, offset);
    }
}

pub fn disassemble_instr(ch: Chunk, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset});

    if (0 < offset and ch.lines.items[offset] == ch.lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:4} ", .{ch.lines.items[offset]});
    }

    const instr = ch.code.items[offset];
    switch (instr) {
        @intFromEnum(Op_Code.Constant) => return constant_instr("Constant", ch, offset),
        @intFromEnum(Op_Code.Negate) => return simple_instr("Negate", offset),
        @intFromEnum(Op_Code.Add) => return simple_instr("Add", offset),
        @intFromEnum(Op_Code.Subtract) => return simple_instr("Subtract", offset),
        @intFromEnum(Op_Code.Multiply) => return simple_instr("Multiply", offset),
        @intFromEnum(Op_Code.Divide) => return simple_instr("Divide", offset),
        @intFromEnum(Op_Code.Return) => return simple_instr("Return", offset),
        else => {
            std.debug.print("Unknown opcode {d}\n", .{instr});
            return offset + 1;
        },
    }
}

pub fn constant_instr(name: []const u8, ch: Chunk, offset: usize) usize {
    const constant_idx = ch.code.items[offset + 1];
    std.debug.print("{s: <16} {d:4} '", .{ name, constant_idx });
    value.print_val(ch.constants.items[constant_idx]);
    std.debug.print("'\n", .{});
    return offset + 2;
}

pub fn simple_instr(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}
