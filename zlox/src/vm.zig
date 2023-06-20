const std = @import("std");
const builtin = @import("builtin");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const debug = @import("debug.zig");
const compiler = @import("compiler.zig");

const stack_max = 256;

pub const VM = struct {
    chunk: chunk.Chunk,
    ip: [*]u8,
    stack: [stack_max]value.Value,
    stack_top: [*]value.Value,
    alloc: std.mem.Allocator,
};

pub const Interpret_Error = error{
    Ok,
    Compile_Error,
    Runtime_Error,
};

pub fn init(alloc: std.mem.Allocator) VM {
    return .{
        .chunk = undefined,
        .ip = undefined,
        .stack = undefined,
        .stack_top = undefined,
        .alloc = alloc,
    };
}

pub fn deinit(m: *VM) void {
    _ = m;
}

pub fn interpret(m: *VM, source: []const u8) Interpret_Error!void {
    var c = compiler.compile(m.alloc, source) catch {
        return error.Compile_Error;
    };
    defer chunk.deinit_chunk(&c);

    std.debug.print("HERE\n", .{});

    m.chunk = c;
    m.ip = @ptrCast([*]u8, m.chunk.code.items.ptr);
    reset_stack(m);

    return run(m);
}

fn reset_stack(m: *VM) void {
    m.stack_top = @ptrCast([*]value.Value, &m.stack[0]);
}

fn run(m: *VM) Interpret_Error!void {
    while (true) {
        if (builtin.mode == .Debug) {
            std.debug.print("          ", .{});

            var slot = @ptrCast([*]value.Value, &m.stack[0]);
            while (slot != m.stack_top) : (slot += 1) {
                std.debug.print("[ ", .{});
                value.print(slot[0]) catch {};
                std.debug.print(" ]", .{});
            }
            std.debug.print("\n", .{});

            const offset = @ptrToInt(m.ip) - @ptrToInt(m.chunk.code.items.ptr);
            _ = debug.disassemble_instruction(m.chunk, offset);
        }

        var instruction = read_byte_code(m);
        switch (instruction) {
            .Return => {
                value.print(stack_pop(m)) catch {};
                std.debug.print("\n", .{});
                return;
            },
            .Constant => {
                const constant = read_constant(m);
                stack_push(m, constant);
            },
            .Add => {
                binary_op(m, '+');
            },
            .Subtract => {
                binary_op(m, '-');
            },
            .Multiply => {
                binary_op(m, '*');
            },
            .Divide => {
                binary_op(m, '/');
            },
            .Negate => {
                stack_push(m, (-stack_pop(m)));
            },
        }
    }
}

fn binary_op(m: *VM, comptime op: u8) void {
    const b = stack_pop(m);
    const a = stack_pop(m);

    const result = switch (op) {
        '+' => a + b,
        '-' => a - b,
        '*' => a * b,
        '/' => a / b,
        else => @compileError("invalid binary operator"),
    };

    stack_push(m, result);
}

fn read_byte(m: *VM) u8 {
    // TODO(sezoka): add bounds check maybe
    const byte = m.ip[0];
    m.ip += 1;
    return byte;
}

fn read_byte_code(m: *VM) chunk.Op_Code {
    return @intToEnum(chunk.Op_Code, read_byte(m));
}

fn read_constant(m: *VM) value.Value {
    const idx = read_byte(m);
    return m.chunk.constants.items[idx];
}

fn stack_push(m: *VM, v: value.Value) void {
    m.stack_top[0] = v;
    m.stack_top += 1;
}

fn stack_pop(m: *VM) value.Value {
    m.stack_top -= 1;
    return m.stack_top[0];
}
