const std = @import("std");
const io = @import("./io.zig");

pub const Value = f32;

pub fn print(v: Value) void {
    io.print("{d:.1}", .{v});
}
