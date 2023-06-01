const std = @import("std");
const Allocator = std.mem.Allocator;
const Value_Array = @import("./value.zig").Value_Array;
const Value = @import("./value.zig").Value;

pub const Op_Code = enum(u8) {
    op_add,
    op_constant,
    op_constant_long,
    op_divide,
    op_false,
    op_pop,
    op_get_local,
    op_get_global,
    op_define_global,
    op_set_local,
    op_set_global,
    op_equal,
    op_greater,
    op_less,
    op_multiply,
    op_print,
    op_negate,
    op_nil,
    op_not,
    op_return,
    op_subtract,
    op_true,

    const Self = @This();

    pub fn byte(self: Self) u8 {
        return @enumToInt(self);
    }
};

const Code_Array = std.ArrayList(u8);
const Line = u16;
const Lines_Array = std.ArrayList(Line);

pub const Chunk = struct {
    code: Code_Array,
    constants: Value_Array,
    lines: Lines_Array,
    alloc: Allocator,

    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        return Self{
            .code = Code_Array.init(alloc),
            .constants = Value_Array.init(alloc),
            .lines = Lines_Array.init(alloc),
            .alloc = alloc,
        };
    }

    pub fn deinit(self: Self) void {
        self.code.deinit();
        self.constants.deinit();
        self.lines.deinit();
    }

    pub fn append_byte(self: *Self, byte: u8, line: Line) Allocator.Error!void {
        try self.code.append(byte);
        try self.lines.append(line);
    }

    pub fn append_constant(self: *Self, constant: Value, line: Line) Allocator.Error!void {
        const const_idx = try self.add_constant(constant);

        if (255 < const_idx) {
            try self.append_byte(Op_Code.op_constant_long.byte(), line);
            const hi = @intCast(u8, const_idx >> 8);
            const lo = @intCast(u8, const_idx & 0xFF);
            try self.append_byte(hi, line);
            try self.append_byte(lo, line);
        } else {
            try self.append_byte(Op_Code.op_constant.byte(), line);
            try self.append_byte(@intCast(u8, const_idx), line);
        }
    }

    pub fn add_constant(self: *Self, constant: Value) Allocator.Error!u16 {
        try self.constants.append(constant);
        return @intCast(u16, self.constants.items.len - 1);
    }
};
