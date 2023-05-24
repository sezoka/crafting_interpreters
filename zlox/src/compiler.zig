const std = @import("std");
const Scanner = @import("./scanner.zig").Scanner;

pub fn compile(source: []const u8) void {
    var scanner = Scanner.init(source);
    var line: usize = 0;

    while (true) {
        const token = scanner.next();
        if (token.line != line) {
            std.debug.print("{d:4} ", .{token.line});
            line = token.line;
        } else {
            std.debug.print("   | ", .{});
        }
        std.debug.print("{d:2} '{s}'\n", .{ token.line, token.lexeme });

        if (token.kind == .eof) break;
    }
}
