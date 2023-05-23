const std = @import("std");

pub const Value = f32;

pub const Value_Array = std.ArrayList(Value);

pub fn print(value: Value) void {
    std.debug.print("{d:.1}", .{value});
}
