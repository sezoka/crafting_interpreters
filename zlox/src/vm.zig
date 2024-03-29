const std = @import("std");

const chunk = @import("chunk.zig");
const compiler = @import("compiler.zig");
const debug = @import("debug.zig");
const object = @import("object.zig");
const table = @import("table.zig");
const value = @import("value.zig");

const Chunk = chunk.Chunk;
const Obj = object.Obj;
const Obj_String = object.Obj_String;
const Obj_String_Set = table.Obj_String_Set;
const Obj_String_Map = table.Obj_String_Map;
const Op_Code = chunk.Op_Code;
const Value = value.Value;

const Interpret_Error = error{ Runtime, Comptime, OutOfMemory };

const Interpret_Result = Interpret_Error!void;

pub const VM = struct {
    ally: std.mem.Allocator,
    chunk: *Chunk,
    ip: [*]u8,
    stack: std.ArrayList(Value),
    objects: ?*Obj,
    strings: Obj_String_Set,
    globals: Obj_String_Map,
};

pub fn create(ally: std.mem.Allocator) VM {
    return .{
        .chunk = undefined,
        .ip = undefined,
        .stack = std.ArrayList(Value).init(ally),
        .objects = null,
        .ally = ally,
        .strings = Obj_String_Set.init(ally),
        .globals = Obj_String_Map.init(ally),
    };
}

pub fn deinit(vm: *VM) void {
    vm.stack.deinit();
    vm.strings.deinit();
    vm.globals.deinit();
    free_objects(vm);
}

fn free_objects(vm: *VM) void {
    var obj = vm.objects;
    while (obj != null) {
        const next = obj.?.next;
        free_object(vm, obj.?);
        obj = next;
    }
}

fn free_object(vm: *VM, obj: *Obj) void {
    switch (obj.kind) {
        .string => {
            const string = @as(*Obj_String, @alignCast(@ptrCast(obj)));
            vm.ally.free(string.chars);
            vm.ally.destroy(string);
        },
    }
}

fn stack_push(vm: *VM, val: Value) !void {
    try vm.stack.append(val);
}

fn stack_pop(vm: *VM) Value {
    return vm.stack.pop();
}

pub fn interpret(vm: *VM, source: []const u8) Interpret_Result {
    var ch = chunk.create(vm.ally);
    defer chunk.deinit(ch);

    if (!try compiler.compile(vm, source, &ch)) {
        return Interpret_Error.Comptime;
    }

    vm.chunk = &ch;
    vm.ip = vm.chunk.code.items.ptr;

    const result = run(vm);

    return result;
}

fn run(vm: *VM) Interpret_Result {
    const util = struct {
        pub fn binary_op(v: *VM, op: Op_Code) !void {
            if (!value.is_number(peek(v, 0)) or !value.is_number(peek(v, 1))) {
                runtime_error(v, "Operands must be numbers.", .{});
                return error.Runtime;
            }
            const b = value.as_float(stack_pop(v));
            const a = value.as_float(stack_pop(v));
            try stack_push(v, switch (op) {
                .Add => value.from_float(a + b),
                .Subtract => value.from_float(a - b),
                .Multiply => value.from_float(a * b),
                .Greater => value.from_bool(a > b),
                .Less => value.from_bool(a < b),
                .Divide => value.from_float(a / b),
                else => unreachable,
            });
        }
    };

    while (true) {
        if (false) {
            std.debug.print("COMMAND:\n", .{});
            std.debug.print("          ", .{});
            _ = debug.disassemble_instr(vm.chunk.*, @intFromPtr(vm.ip) - @intFromPtr(vm.chunk.code.items.ptr));
            std.debug.print("\nSTACK:\n", .{});
            for (vm.stack.items) |slot| {
                std.debug.print("[ ", .{});
                value.print_val(slot);
                std.debug.print(" ]", .{});
            }
            // std.debug.print("\n", .{});

            // std.debug.print("\nGLOBALS:\n", .{});
            // var iter = vm.globals.valueIterator();
            // while (iter.next()) |slot| {
            //     std.debug.print("[ ", .{});
            //     value.print_val(slot.*);
            //     std.debug.print(" ]", .{});
            // }
            // std.debug.print("\n", .{});

            // std.debug.print("\nCONSTANTS:\n", .{});
            // for (vm.chunk.constants.items) |slot| {
            //     std.debug.print("[ ", .{});
            //     value.print_val(slot);
            //     std.debug.print(" ]", .{});
            // }

            std.debug.print("\n-----------\n", .{});
        }

        const instr = read_byte(vm);
        try switch (instr) {
            @intFromEnum(Op_Code.Constant) => {
                const constant = read_constant(vm);
                try stack_push(vm, constant);
            },
            @intFromEnum(Op_Code.Negate) => {
                if (!value.is_number(peek(vm, 0))) {
                    runtime_error(vm, "Operand must be a number", .{});
                    return error.Runtime;
                }
                try stack_push(vm, value.from_float(-value.as_float(stack_pop(vm))));
            },
            @intFromEnum(Op_Code.Nil) => stack_push(vm, .nil),
            @intFromEnum(Op_Code.True) => stack_push(vm, value.from_bool(true)),
            @intFromEnum(Op_Code.False) => stack_push(vm, value.from_bool(false)),
            @intFromEnum(Op_Code.Pop) => {
                _ = stack_pop(vm);
            },
            @intFromEnum(Op_Code.Get_Local) => {
                const slot = read_byte(vm);
                try stack_push(vm, vm.stack.items[slot]);
            },
            @intFromEnum(Op_Code.Set_Local) => {
                const slot = read_byte(vm);
                vm.stack.items[slot] = peek(vm, 0);
            },
            @intFromEnum(Op_Code.Get_Global) => {
                const name = try read_string(vm);
                if (vm.globals.get(name)) |val| {
                    try stack_push(vm, val);
                } else {
                    runtime_error(vm, "Undefined variable '{s}'.", .{name.chars});
                    return error.Runtime;
                }
            },
            @intFromEnum(Op_Code.Define_Global) => {
                const name = try read_string(vm);
                try vm.globals.put(name, peek(vm, 0));
                _ = stack_pop(vm);
            },
            @intFromEnum(Op_Code.Set_Global) => {
                const name = try read_string(vm);
                if (vm.globals.contains(name)) {
                    try vm.globals.put(name, peek(vm, 0));
                } else {
                    runtime_error(vm, "Undefined variable '{s}'", .{name.chars});
                    return error.Runtime;
                }
            },
            @intFromEnum(Op_Code.Equal) => {
                const b = stack_pop(vm);
                const a = stack_pop(vm);
                try stack_push(vm, value.from_bool(value.equal(a, b)));
            },
            @intFromEnum(Op_Code.Greater) => util.binary_op(vm, .Greater),
            @intFromEnum(Op_Code.Less) => util.binary_op(vm, .Less),
            @intFromEnum(Op_Code.Add) => {
                if (object.is_string(peek(vm, 0)) and object.is_string(peek(vm, 1))) {
                    try concatenate(vm);
                } else if (value.is_number(peek(vm, 0)) and value.is_number(peek(vm, 1))) {
                    const b = value.as_float(stack_pop(vm));
                    const a = value.as_float(stack_pop(vm));
                    try stack_push(vm, value.from_float(a + b));
                } else {
                    runtime_error(vm, "Operands must be two numbers or 2 strings.", .{});
                    return error.Runtime;
                }
            },
            @intFromEnum(Op_Code.Subtract) => util.binary_op(vm, .Subtract),
            @intFromEnum(Op_Code.Multiply) => util.binary_op(vm, .Multiply),
            @intFromEnum(Op_Code.Divide) => util.binary_op(vm, .Divide),
            @intFromEnum(Op_Code.Not) => stack_push(vm, value.from_bool(is_falsey(stack_pop(vm)))),
            @intFromEnum(Op_Code.Print) => {
                value.print_val(stack_pop(vm));
                std.debug.print("\n", .{});
            },
            @intFromEnum(Op_Code.Jump) => {
                const offset = read_short(vm);
                vm.ip += offset;
            },
            @intFromEnum(Op_Code.Jump_If_False) => {
                const offset = read_short(vm);
                if (is_falsey(peek(vm, 0))) {
                    vm.ip += offset;
                }
            },
            @intFromEnum(Op_Code.Loop) => {
                const offset = read_short(vm);
                vm.ip -= offset;
            },
            @intFromEnum(Op_Code.Return) => return,
            else => unreachable,
        };
    }
}

fn read_short(vm: *VM) u16 {
    const short = (@as(u16, @intCast(vm.ip[0])) << 8) | (@as(u16, @intCast(vm.ip[1])));
    vm.ip += 2;
    return short;
}

fn read_string(vm: *VM) !*Obj_String {
    return object.as_string(read_constant(vm));
}

fn concatenate(vm: *VM) !void {
    const b = object.as_string(stack_pop(vm));
    const a = object.as_string(stack_pop(vm));
    const chars = try std.mem.concat(vm.ally, u8, &[2][]const u8{ a.chars, b.chars });

    const result = try object.take_string(vm, chars);
    try stack_push(vm, value.from_obj(result));
}

fn is_falsey(val: Value) bool {
    return value.is_nil(val) or (value.is_bool(val) and !value.as_bool(val));
}

fn runtime_error(vm: *VM, comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);

    const instr = @intFromPtr(vm.ip) - @intFromPtr(vm.chunk.code.items.ptr);
    const line = vm.chunk.lines.items[instr];
    std.debug.print("[line {d}] in script\n", .{line});
    reset_stack(vm);
}

fn reset_stack(vm: *VM) void {
    vm.stack.clearRetainingCapacity();
}

fn peek(vm: *VM, dist: usize) Value {
    return vm.stack.items[vm.stack.items.len - dist - 1];
}

fn read_constant(vm: *VM) Value {
    return vm.chunk.constants.items[@intCast(read_byte(vm))];
}

fn read_byte(vm: *VM) u8 {
    const byte = vm.ip[0];
    vm.ip += 1;
    return byte;
}
