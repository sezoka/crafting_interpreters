const std = @import("std");

pub const Value = f64;

pub const Value_Array = std.ArrayList(Value);

pub fn print_val(val: Value) void {
    std.debug.print("{d}", .{val});
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
