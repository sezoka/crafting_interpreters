const std = @import("std");
const io = @import("./io.zig");

pub const Value = f32;

pub fn print(v: Value) void {
    print_with_writer(v, std.io.getStdOut().writer());
}

pub fn print_debug(v: Value) void {
    print_with_writer(v, std.io.getStdErr().writer());
}

pub fn print_with_writer(v: Value, writer: anytype) void {
    writer.print("{d:.2}", .{v}) catch unreachable;
}
