const std = @import("std");
const chunk = @import("./chunk.zig");
const value = @import("./value.zig");
const debug = @import("./debug.zig");
const io = @import("./io.zig");
const Chunk = chunk.Chunk;
const Op_Code = chunk.Op_Code;
const Value = value.Value;

pub const Interpret_Error = error{
    Compile_Error,
    Runtime_Error,
};

pub const Interpret_Result = Interpret_Error!void;

const stack_max = 256;

pub const VM = struct {
    chunk: ?Chunk,
    ip: ?[*]Op_Code,
    stack: [stack_max]Value,
    stack_top: [*]Value,
};

pub fn init() VM {
    const vm = .{
        .chunk = null,
        .ip = null,
        .stack = [_]Value{0.0} ** stack_max,
        .stack_top = undefined,
    };
    return vm;
}

pub fn deinit(vm: *VM) void {
    vm.chunk = null;
}

pub fn interpret(vm: *VM, ch: Chunk) Interpret_Result {
    vm.chunk = ch;
    vm.ip = @ptrCast(&ch.code.items[0]);
    vm.stack_top = @ptrCast(&vm.stack[0]);
    return run(vm);
}

fn run(vm: *VM) Interpret_Result {
    if (vm.chunk) |ch|
        while (true) {
            if (debug.enabled) {
                std.debug.print("          ", .{});
                var slot: [*]Value = @ptrCast(&vm.stack[0]);
                while (@intFromPtr(slot) < @intFromPtr(vm.stack_top)) : (slot += 1) {
                    std.debug.print("[ ", .{});
                    value.print_debug(slot[0]);
                    std.debug.print(" ]", .{});
                }
                std.debug.print("\n", .{});
                _ = debug.disassemble_instruction(ch, (@intFromPtr(vm.ip) - @intFromPtr(&ch.code.items[0])) / 2); // 2 - in bytes
            }
            var instr = read_instr(vm) orelse unreachable;
            switch (instr) {
                .return_ => {
                    value.print(stack_pop(vm));
                    io.print("\n", .{});
                    return;
                },
                .constant => |id| {
                    const constant = ch.constants.items[id];
                    stack_push(vm, constant);
                },
                .negate => {
                    stack_push(vm, -stack_pop(vm));
                },
                .add => binary_op(vm, '+'),
                .subtract => binary_op(vm, '-'),
                .multiply => binary_op(vm, '*'),
                .divide => binary_op(vm, '/'),
            }
        };
}

fn binary_op(vm: *VM, comptime op: u8) void {
    const b = stack_pop(vm);
    const a = stack_pop(vm);
    const result = switch (op) {
        '+' => a + b,
        '-' => a - b,
        '*' => a * b,
        '/' => a / b,
        else => @compileError("unhandled op"),
    };
    stack_push(vm, result);
}

fn stack_push(vm: *VM, v: Value) void {
    vm.stack_top[0] = v;
    vm.stack_top += 1;
}

fn stack_pop(vm: *VM) Value {
    vm.stack_top -= 1;
    return vm.stack_top[0];
}

fn read_instr(vm: *VM) ?Op_Code {
    if (vm.ip) |*ip| {
        const instr = ip.*[0];
        ip.* += 1;
        return instr;
    }
    return null;
}
