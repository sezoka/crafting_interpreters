const std = @import("std");
const chunk = @import("chunk.zig");
const value = @import("value.zig");

pub fn disassemble_chunk(c: chunk.Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < c.code.items.len) {
        offset = disassemble_instruction(c, offset);
    }
}

pub fn disassemble_instruction(c: chunk.Chunk, offset: usize) usize {
    std.debug.print("{d:0<4} ", .{offset});

    if (0 < offset and
        c.lines.items[offset] == c.lines.items[offset - 1])
    {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:4} ", .{c.lines.items[offset]});
    }

    const instruction = c.code.items[offset];
    return switch (@enumFromInt(chunk.Op_Code, instruction)) {
        .Return => simple_instruction("Return", offset),
        .Constant => constant_instruction("Constant", c, offset),
        .Nil => simple_instruction("Nil", offset),
        .True => simple_instruction("True", offset),
        .False => simple_instruction("False", offset),
        .Pop => simple_instruction("Pop", offset),
        .Get_Global => constant_instruction("Get_Global", c, offset),
        .Define_Global => constant_instruction("Define_Global", c, offset),
        .Set_Global => constant_instruction("Set_Global", c, offset),
        .Equal => simple_instruction("Equal", offset),
        .Greater => simple_instruction("Greater", offset),
        .Less => simple_instruction("Less", offset),
        .Add => simple_instruction("Add", offset),
        .Subtract => simple_instruction("Subtract", offset),
        .Multiply => simple_instruction("Multiply", offset),
        .Divide => simple_instruction("Divide", offset),
        .Not => simple_instruction("Not", offset),
        .Print => simple_instruction("Print", offset),
        .Negate => simple_instruction("Negate", offset),
    };
}

fn simple_instruction(name: []const u8, offset: usize) usize {
    std.debug.print("{s}\n", .{name});
    return offset + 1;
}

fn constant_instruction(name: []const u8, c: chunk.Chunk, offset: usize) usize {
    const constant_idx = c.code.items[offset + 1];
    const constant = c.constants.items[constant_idx];
    std.debug.print("{s: <16} '", .{name});
    value.print_value(constant) catch {};
    std.debug.print("'\n", .{});
    return offset + 2;
}
