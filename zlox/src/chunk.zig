const std = @import("std");
const Value = @import("./value.zig").Value;

pub const Op_Code = union(enum) {
    return_,
    constant: u8,
    negate,
    add,
    subtract,
    multiply,
    divide,
};

pub const Chunk = struct {
    code: std.ArrayList(Op_Code),
    constants: std.ArrayList(Value),
    lines: std.ArrayList(u16),
    ally: std.mem.Allocator,
};

pub fn init(ally: std.mem.Allocator) Chunk {
    return .{
        .code = std.ArrayList(Op_Code).init(ally),
        .constants = std.ArrayList(Value).init(ally),
        .lines = std.ArrayList(u16).init(ally),
        .ally = ally,
    };
}

pub fn deinit(ch: Chunk) void {
    ch.code.deinit();
    ch.constants.deinit();
    ch.lines.deinit();
}

pub fn write(ch: *Chunk, code: Op_Code, line: u16) !void {
    try ch.code.append(code);
    try ch.lines.append(line);
}

pub fn add_constant(ch: *Chunk, constant: Value) !u8 {
    try ch.constants.append(constant);
    return @intCast(ch.constants.items.len - 1);
}
