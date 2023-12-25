const std = @import("std");
const value = @import("value.zig");
const Value_Array = value.Value_Array;
const Value = value.Value;

pub const Op_Code = enum(u8) {
    Constant,
    Add,
    Subtract,
    Multiply,
    Divide,
    Negate,
    Return,
};

pub const Chunk = struct {
    code: std.ArrayList(u8),
    lines: std.ArrayList(u32),
    constants: Value_Array,
};

pub fn create(ally: std.mem.Allocator) Chunk {
    return .{
        .code = std.ArrayList(u8).init(ally),
        .lines = std.ArrayList(u32).init(ally),
        .constants = value.create_arr(ally),
    };
}

pub fn write_byte(ch: *Chunk, byte: u8, line: u32) !void {
    try ch.code.append(byte);
    try ch.lines.append(line);
}

pub fn write(ch: *Chunk, code: Op_Code, line: u32) !void {
    try write_byte(ch, @intFromEnum(code), line);
}

pub fn add_constant(ch: *Chunk, v: value.Value) !u8 {
    try value.write_arr(&ch.constants, v);
    return @as(u8, @intCast(ch.constants.items.len)) - 1;
}

pub fn deinit(ch: Chunk) void {
    ch.code.deinit();
    ch.lines.deinit();
    value.deinit_arr(ch.constants);
}
