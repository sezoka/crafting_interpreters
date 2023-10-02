const std = @import("std");

pub fn print(comptime fmt: []const u8, params: anytype) void {
    const writer = std.io.getStdOut().writer();
    writer.print(fmt, params) catch unreachable;
}
