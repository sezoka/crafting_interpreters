const std = @import("std");

const vm = @import("vm.zig");
const chunk = @import("chunk.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const ally = gpa.allocator();

    var vm_inst = vm.create(ally);
    defer vm.deinit(&vm_inst);

    var args = try std.process.argsWithAllocator(ally);
    defer args.deinit();

    _ = args.skip();
    const file_path = args.next() orelse {
        try repl(&vm_inst);
        return;
    };

    try run_file(&vm_inst, file_path);

    // if (!args.skip()) {
    //     std.debug.print("Usage: clox [path]\n", .{});
    //     return;
    // }
}

fn repl(v: *vm.VM) !void {
    var line = std.ArrayList(u8).init(v.ally);
    defer line.deinit();

    while (true) {
        std.debug.print("> ", .{});

        std.io.getStdIn().reader().readUntilDelimiterArrayList(&line, '\n', 1024) catch {
            std.debug.print("\n", .{});
            break;
        };

        try vm.interpret(v, line.items);

        line.clearAndFree();
    }
}

fn run_file(v: *vm.VM, path: []const u8) !void {
    const source = read_file(v.ally, path) orelse return;
    defer v.ally.free(source);
    const result = vm.interpret(v, source);
    if (result == error.Runtime) std.debug.print("UPAL V RUNTIME\n", .{});
    if (result == error.Comptime) std.debug.print("UPAL V COMPTIME\n", .{});
}

fn read_file(ally: std.mem.Allocator, path: []const u8) ?[]const u8 {
    const src = std.fs.cwd().readFileAlloc(ally, path, 4086) catch {
        std.debug.print("Could not open '{s}'.\n", .{path});
        return null;
    };
    return src;
}
