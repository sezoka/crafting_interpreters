const std = @import("std");
const scanner = @import("scanner.zig");

pub fn compile(alloc: std.mem.Allocator, source: []const u8) !void {
    _ = alloc;

    var s = scanner.init_scanner(source);
    var line: u32 = std.math.maxInt(u32);

    while (true) {
        const token = try scanner.scan_token(&s);
        if (token.line != line) {
            std.debug.print("{d:4} ", .{token.line});
            line = token.line;
        } else {
            std.debug.print("   | ", .{});
        }
        std.debug.print("{} '{s}'\n", .{ token.kind, token.literal });

        if (token.kind == .Eof) break;
    }
}
