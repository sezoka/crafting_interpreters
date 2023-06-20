const std = @import("std");
const value = @import("value.zig");

pub const Op_Code = enum {
    Return,
    Constant,
    Add,
    Subtract,
    Multiply,
    Divide,
    Negate,
};

pub const Byte_Array = std.ArrayList(u8);

pub const Line_Array = std.ArrayList(u32);

pub const Chunk = struct {
    code: Byte_Array,
    constants: value.Value_Array,
    lines: Line_Array,
};

pub fn init_chunk(alloc: std.mem.Allocator) Chunk {
    return .{
        .code = Byte_Array.init(alloc),
        .constants = value.Value_Array.init(alloc),
        .lines = Line_Array.init(alloc),
    };
}

pub fn deinit_chunk(c: *const Chunk) void {
    c.code.deinit();
    c.constants.deinit();
    c.lines.deinit();
}

pub fn append_byte(c: *Chunk, byte: u8, line: u32) !void {
    try c.code.append(byte);
    try c.lines.append(line);
}

pub fn append_byte_code(c: *Chunk, code: Op_Code, line: u32) !void {
    try append_byte(c, @enumToInt(code), line);
}

pub fn append_constant(c: *Chunk, v: value.Value) !void {
    try c.constants.append(v);
}

pub fn add_constant(c: *Chunk, v: value.Value) !usize {
    try append_constant(c, v);
    return c.constants.items.len - 1;
}
