const std = @import("std");

pub const Value_Kind = enum {
    bool,
    number,
    nil,
};

pub const Value = union(Value_Kind) {
    bool: bool,
    number: f64,
    nil,
};

pub fn is_bool(v: Value) bool {
    return v == Value_Kind.bool;
}

pub fn is_number(v: Value) bool {
    return v == Value_Kind.number;
}

pub fn is_nil(v: Value) bool {
    return v == Value_Kind.nil;
}

pub fn from_bool(b: bool) Value {
    return .{ .bool = b };
}

pub fn from_float(f: f64) Value {
    return .{ .number = f };
}

pub fn from_null() Value {
    return .{ .nil = null };
}

pub fn as_float(v: Value) f64 {
    return v.number;
}

pub fn as_bool(v: Value) bool {
    return v.bool;
}

pub fn equal(a: Value, b: Value) bool {
    if (@intFromEnum(a) != @intFromEnum(b)) return false;
    switch (a) {
        .number => |a_num| return a_num == b.number,
        .bool => |a_bool| return a_bool == b.bool,
        .nil => return true,
        // else => return false,
    }
}

pub const Value_Array = std.ArrayList(Value);

pub fn print_val(val: Value) void {
    switch (val) {
        .bool => |b| std.debug.print("{}", .{b}),
        .nil => std.debug.print("nil", .{}),
        .number => |n| std.debug.print("{d}", .{n}),
    }
}

pub fn create_arr(ally: std.mem.Allocator) Value_Array {
    return Value_Array.init(ally);
}

pub fn write_arr(va: *Value_Array, v: Value) !void {
    try va.append(v);
}

pub fn deinit_arr(va: Value_Array) void {
    va.deinit();
}
