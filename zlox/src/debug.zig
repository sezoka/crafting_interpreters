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
        offset = disassemble_instr(ch, offset);
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
        @intFromEnum(Op_Code.Nil) => return simple_instr("Nil", offset),
        @intFromEnum(Op_Code.True) => return simple_instr("True", offset),
        @intFromEnum(Op_Code.False) => return simple_instr("False", offset),
        @intFromEnum(Op_Code.Get_Local) => return byte_instr("Get_Local", ch, offset),
        @intFromEnum(Op_Code.Set_Local) => return byte_instr("Set_Local", ch, offset),
        @intFromEnum(Op_Code.Define_Global) => return constant_instr("Define_Global", ch, offset),
        @intFromEnum(Op_Code.Set_Global) => return constant_instr("Set_Global", ch, offset),
        @intFromEnum(Op_Code.Equal) => return simple_instr("Equal", offset),
        @intFromEnum(Op_Code.Pop) => return simple_instr("Pop", offset),
        @intFromEnum(Op_Code.Greater) => return simple_instr("Greater", offset),
        @intFromEnum(Op_Code.Less) => return simple_instr("Less", offset),
        @intFromEnum(Op_Code.Negate) => return simple_instr("Negate", offset),
        @intFromEnum(Op_Code.Add) => return simple_instr("Add", offset),
        @intFromEnum(Op_Code.Subtract) => return simple_instr("Subtract", offset),
        @intFromEnum(Op_Code.Multiply) => return simple_instr("Multiply", offset),
        @intFromEnum(Op_Code.Divide) => return simple_instr("Divide", offset),
        @intFromEnum(Op_Code.Not) => return simple_instr("Not", offset),
        @intFromEnum(Op_Code.Print) => return simple_instr("Print", offset),
        @intFromEnum(Op_Code.Jump) => return jump_instruction("Jump", 1, ch, offset),
        @intFromEnum(Op_Code.Jump_If_False) => return jump_instruction("Jump_If_False", 1, ch, offset),
        @intFromEnum(Op_Code.Loop) => return jump_instruction("Loop", -1, ch, offset),
        @intFromEnum(Op_Code.Return) => return simple_instr("Return", offset),
        else => {
            std.debug.print("Unknown opcode {d}\n", .{instr});
            return offset + 1;
        },
    }
}

pub fn jump_instruction(name: []const u8, sigh: i32, ch: Chunk, offset: usize) usize {
    var jump = @as(u16, @intCast(ch.code.items[offset + 1])) << 8;
    jump |= ch.code.items[offset + 2];
    std.debug.print("{s:<16} {d:4} -> {d}\n", .{ name, offset, @as(i32, @intCast(offset + 3)) + sigh * jump });
    return offset + 3;
}

pub fn byte_instr(name: []const u8, ch: Chunk, offset: usize) usize {
    const slot = ch.code.items[offset + 1];
    std.debug.print("{s:<16} {d:4}\n", .{ name, slot });
    return offset + 2;
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
