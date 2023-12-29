const std = @import("std");
const object = @import("object.zig");
const Obj_Kind = object.Obj_Kind;
const Obj = object.Obj;

pub const Value_Kind = enum {
    bool,
    number,
    obj,
    nil,
};

pub const Value = union(Value_Kind) {
    bool: bool,
    number: f64,
    obj: *Obj,
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

pub fn is_obj(v: Value) bool {
    return v == Value_Kind.obj;
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

pub fn from_obj(o: anytype) Value {
    return .{ .obj = @ptrCast(o) };
}

pub fn as_float(v: Value) f64 {
    return v.number;
}

pub fn as_bool(v: Value) bool {
    return v.bool;
}

pub fn as_obj(v: Value) *Obj {
    return v.obj;
}

pub fn equal(a: Value, b: Value) bool {
    if (@intFromEnum(a) != @intFromEnum(b)) return false;
    switch (a) {
        .number => |a_num| return a_num == b.number,
        .bool => |a_bool| return a_bool == b.bool,
        .nil => return true,
        .obj => {
            const a_str = object.as_string_slice(a);
            const b_str = object.as_string_slice(b);
            return a_str.len == b_str.len and std.mem.eql(u8, a_str, b_str);
        },
    }
}

pub const Value_Array = std.ArrayList(Value);

pub fn print_val(val: Value) void {
    switch (val) {
        .bool => |b| std.debug.print("{}", .{b}),
        .nil => std.debug.print("nil", .{}),
        .number => |n| std.debug.print("{d}", .{n}),
        .obj => object.print_obj(val),
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
