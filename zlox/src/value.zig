const std = @import("std");

pub const Value = f64;

pub const Value_Array = std.ArrayList(Value);

pub fn print(v: Value) !void {
    const writer = std.io.getStdOut().writer();
    try print_with_writer(writer, v);
}

pub fn print_with_writer(w: anytype, v: Value) !void {
    try w.print("{d}", .{v});
}
