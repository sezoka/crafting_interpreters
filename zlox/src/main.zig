const std = @import("std");
const debug = @import("debug.zig");
const config = @import("config.zig");
const chunk = @import("chunk.zig");
const vm = @import("vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var m = vm.init_vm(alloc);
    defer vm.deinit(&m);

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len == 1) {
        try repl(&m);
    } else if (args.len == 2) {
        try run_file(&m, args[1]);
    } else {
        std.log.info("Usage: clox [path]\n", .{});
        return;
    }
}

fn repl(m: *vm.VM) !void {
    var line = std.ArrayList(u8).init(m.alloc);
    defer line.deinit();

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    while (true) {
        try stdout.writeAll("> ");
        stdin.readUntilDelimiterArrayList(&line, '\n', 1024) catch |err| {
            if (err == error.EndOfStream) break;
        };
        if (line.items.len == 0) continue;
        vm.interpret(m, line.items) catch |err| {
            if (config.show_debug_info) {
                return err;
            }
        };

        line.clearAndFree();
    }
}

fn run_file(m: *vm.VM, path: []const u8) !void {
    const source = std.fs.cwd().readFileAlloc(m.alloc, path, 10240) catch |err| {
        switch (err) {
            error.FileTooBig => std.log.err("Not enough memory to read \"{s}\"", .{path}),
            else => std.log.err("Could not open file \"{s}\"", .{path}),
        }
        return;
    };
    defer m.alloc.free(source);

    vm.interpret(m, source) catch |err| {
        if (config.show_debug_info) {
            return err;
        }
    };
}
