const std = @import("std");
const Chunk = @import("./chunk.zig").Chunk;
const Op_Code = @import("./chunk.zig").Op_Code;
const debug = @import("./debug.zig");
const VM = @import("./vm.zig").VM;

fn run_file(vm: *VM, file_path: []const u8) !void {
    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        std.log.err("Could not open file \"{s}\"", .{file_path});
        return error.CouldNotOpenFile;
    };
    defer file.close();

    const file_content = file.reader().readAllAlloc(vm.alloc, 1024000) catch |err| {
        switch (err) {
            error.StreamTooLong => {
                std.log.err("File too big", .{});
            },
            else => {
                std.log.err("Could not read file \"{s}\"", .{file_path});
            },
        }
        return err;
    };
    defer vm.alloc.free(file_content);

    try vm.interpret(file_content);
}

fn repl(vm: *VM) !void {
    var arena = std.heap.ArenaAllocator.init(vm.alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();

    const stdin = std.io.getStdIn();
    const reader = stdin.reader();
    const stdout = std.io.getStdOut();
    const writer = stdout.writer();

    while (true) {
        _ = try writer.write("> ");

        var line = try reader.readUntilDelimiterOrEofAlloc(arena_alloc, '\n', 256) orelse break;
        if (line.len != 0) {
            try vm.interpret(line);
        }

        _ = arena.reset(.retain_capacity);
    }
}

fn main_2() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var args_iter = std.process.args();
    _ = args_iter.skip();

    var vm = VM.init(alloc);
    defer vm.deinit();

    if (args_iter.next()) |file_path| {
        if (args_iter.skip()) {
            std.log.info("Usage: zlox [path]", .{});
            return;
        } else {
            try run_file(&vm, file_path);
        }
    } else {
        try repl(&vm);
    }

    // var chunk = Chunk.init(alloc);
    // defer chunk.deinit();

    // try chunk.append_constant(1.2, 123);
    // try chunk.append_constant(3.4, 123);

    // try chunk.append_byte(Op_Code.op_add.byte(), 123);

    // try chunk.append_constant(5.6, 123);

    // try chunk.append_byte(Op_Code.op_divide.byte(), 123);
    // try chunk.append_byte(Op_Code.op_negate.byte(), 123);

    // try chunk.append_byte(Op_Code.op_return.byte(), 123);

    // try debug.disassemble_chunk(chunk, "test chunk");
}

pub fn main() void {
    main_2() catch |err| std.debug.print("Error Occured {any}\n", .{err});
}
