const std = @import("std");

const chunk = @import("chunk.zig");
const debug = @import("debug.zig");
const value = @import("value.zig");

const Chunk = chunk.Chunk;
const Value = value.Value;
const Op_Code = chunk.Op_Code;

const Interpret_Error = error{ Runtime, Comptime, OutOfMemory };

const Interpret_Result = Interpret_Error!void;

// const STACK_MAX = 256;

const VM = struct {
    chunk: *Chunk,
    ip: [*]u8,
    stack: std.ArrayList(Value),
};

pub fn create(ally: std.mem.Allocator) VM {
    return .{
        .chunk = undefined,
        .ip = undefined,
        .stack = std.ArrayList(Value).init(ally),
    };
}

pub fn deinit(vm: VM) void {
    vm.stack.deinit();
}

fn stack_push(vm: *VM, val: Value) !void {
    try vm.stack.append(val);
}

fn stack_pop(vm: *VM) Value {
    return vm.stack.pop();
}

pub fn interpret(vm: *VM, ch: *Chunk) Interpret_Result {
    vm.chunk = ch;
    vm.ip = @ptrCast(vm.chunk.code.items);
    return run(vm);
}

fn run(vm: *VM) Interpret_Result {
    const util = struct {
        pub fn binary_op(v: *VM, op: Op_Code) !void {
            const b = stack_pop(v);
            const a = stack_pop(v);
            try switch (op) {
                .Add => stack_push(v, a + b),
                .Subtract => stack_push(v, a - b),
                .Multiply => stack_push(v, a * b),
                .Divide => stack_push(v, a / b),
                else => unreachable,
            };
        }
    };

    while (true) {
        if (debug.IS_DEBUG) {
            std.debug.print("          ", .{});
            for (vm.stack.items) |slot| {
                std.debug.print("[ ", .{});
                value.print_val(slot);
                std.debug.print(" ]", .{});
            }
            std.debug.print("\n", .{});
            _ = debug.disassemble_instr(vm.chunk.*, @intFromPtr(vm.ip) - @intFromPtr(vm.chunk.code.items.ptr));
        }
        const instr = read_byte(vm);
        try switch (instr) {
            @intFromEnum(Op_Code.Constant) => {
                const constant = read_constant(vm);
                try stack_push(vm, constant);
            },
            @intFromEnum(Op_Code.Negate) => stack_push(vm, -stack_pop(vm)),
            @intFromEnum(Op_Code.Add) => util.binary_op(vm, .Add),
            @intFromEnum(Op_Code.Subtract) => util.binary_op(vm, .Subtract),
            @intFromEnum(Op_Code.Multiply) => util.binary_op(vm, .Multiply),
            @intFromEnum(Op_Code.Divide) => util.binary_op(vm, .Divide),
            @intFromEnum(Op_Code.Return) => {
                value.print_val(stack_pop(vm));
                std.debug.print("\n", .{});
                return;
            },

            else => unreachable,
        };
    }
}

fn read_constant(vm: *VM) Value {
    return vm.chunk.constants.items[@intCast(read_byte(vm))];
}

fn read_byte(vm: *VM) u8 {
    const byte = vm.ip[0];
    vm.ip += 1;
    return byte;
}
