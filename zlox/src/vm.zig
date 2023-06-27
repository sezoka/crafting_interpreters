const std = @import("std");
const config = @import("config.zig");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const debug = @import("debug.zig");
const compiler = @import("compiler.zig");

const stack_max = 256;

const String_Table = std.StringHashMap(*value.Obj_String);
const Globals_Table = std.AutoHashMap(*value.Obj_String, value.Value);

pub const VM = struct {
    chunk: chunk.Chunk,
    ip: [*]u8,
    stack: [stack_max]value.Value,
    stack_top: [*]value.Value,
    objects: ?*value.Obj,
    strings: String_Table,
    globals: Globals_Table,
    alloc: std.mem.Allocator,
};

pub const Interpret_Error = error{
    Compile_Error,
    Runtime_Error,
};

pub fn init_vm(alloc: std.mem.Allocator) VM {
    return .{
        .chunk = undefined,
        .ip = undefined,
        .stack = undefined,
        .stack_top = undefined,
        .objects = null,
        .strings = String_Table.init(alloc),
        .globals = Globals_Table.init(alloc),
        .alloc = alloc,
    };
}

pub fn deinit(m: *VM) void {
    deinit_objects(m);
    m.strings.deinit();
    m.globals.deinit();
}

fn deinit_objects(m: *VM) void {
    var object = m.objects;
    while (object != null) {
        const next = object.?.next;
        deinit_object(m, object.?);
        object = next;
    }
}

fn deinit_object(m: *VM, obj: *value.Obj) void {
    switch (obj.kind) {
        .String => {
            const string = @fieldParentPtr(value.Obj_String, "obj", obj);
            m.alloc.free(string.chars);
            m.alloc.destroy(string);
        },
        .Function => {
            const function = @fieldParentPtr(value.Obj_Function, "obj", obj);
            chunk.deinit_chunk(&function.chunk);
            m.alloc.destroy(function);
        },
    }
}

pub fn interpret(m: *VM, source: []const u8) Interpret_Error!void {
    var c = compiler.compile(m, source) catch {
        return error.Compile_Error;
    };
    defer chunk.deinit_chunk(&c);

    m.chunk = c;
    m.ip = @ptrCast([*]u8, m.chunk.code.items.ptr);
    reset_stack(m);

    return run(m);
}

fn reset_stack(m: *VM) void {
    m.stack_top = @ptrCast([*]value.Value, &m.stack[0]);
}

fn run(m: *VM) Interpret_Error!void {
    const writer = std.io.getStdOut().writer();

    while (true) {
        if (config.show_debug_info) {
            std.debug.print("          ", .{});

            var slot = @ptrCast([*]value.Value, &m.stack[0]);
            while (slot != m.stack_top) : (slot += 1) {
                std.debug.print("[ ", .{});
                value.print_value(slot[0]) catch {};
                std.debug.print(" ]", .{});
            }
            std.debug.print("\n", .{});

            const offset = @intFromPtr(m.ip) - @intFromPtr(m.chunk.code.items.ptr);
            _ = debug.disassemble_instruction(m.chunk, offset);
        }

        var instruction = read_byte_code(m);
        switch (instruction) {
            .Return => {
                return;
            },
            .Loop => {
                const offset = read_short(m);
                m.ip -= offset;
            },
            .Jump => {
                const offset = read_short(m);
                m.ip += offset;
            },
            .Jump_If_False => {
                const offset = read_short(m);
                if (is_falsey(peek(m, 0))) m.ip += offset;
            },
            .Constant => {
                const constant = read_constant(m);
                stack_push(m, constant);
            },
            .Nil => {
                stack_push(m, value.init_nil());
            },
            .True => {
                stack_push(m, value.init_bool(true));
            },
            .False => {
                stack_push(m, value.init_bool(false));
            },
            .Pop => {
                _ = stack_pop(m);
            },
            .Get_Local => {
                const slot = read_byte(m);
                stack_push(m, m.stack[slot]);
            },
            .Set_Local => {
                const slot = read_byte(m);
                m.stack[slot] = peek(m, 0);
            },
            .Get_Global => {
                const name = read_string(m);
                const val = m.globals.get(name) orelse {
                    runtime_error(m, "Undefined variable '{s}'.", .{name.chars});
                    return Interpret_Error.Runtime_Error;
                };
                stack_push(m, val);
            },
            .Define_Global => {
                const name = read_string(m);
                m.globals.put(name, peek(m, 0)) catch return Interpret_Error.Runtime_Error;
                _ = stack_pop(m);
            },
            .Set_Global => {
                const name = read_string(m);
                if (m.globals.contains(name)) {
                    m.globals.put(name, peek(m, 0)) catch return Interpret_Error.Runtime_Error;
                } else {
                    runtime_error(m, "Undefined variable '{s}'.", .{name.chars});
                    return Interpret_Error.Runtime_Error;
                }
            },
            .Equal => {
                const b = stack_pop(m);
                const a = stack_pop(m);
                stack_push(m, value.init_bool(value.values_equal(a, b)));
            },
            .Greater => {
                try binary_op(m, '>');
            },
            .Less => {
                try binary_op(m, '<');
            },
            .Add => {
                if (value.is_string(peek(m, 0)) and value.is_string(peek(m, 1))) {
                    concatenate(m) catch return Interpret_Error.Runtime_Error;
                } else if (value.is_number(peek(m, 0)) and value.is_number(peek(m, 1))) {
                    const b = value.as_number(stack_pop(m));
                    const a = value.as_number(stack_pop(m));
                    stack_push(m, value.init_number(a + b));
                } else {
                    runtime_error(m, "Operands must be two numbers or two strings.", .{});
                    return Interpret_Error.Runtime_Error;
                }
            },
            .Subtract => {
                try binary_op(m, '-');
            },
            .Multiply => {
                try binary_op(m, '*');
            },
            .Divide => {
                try binary_op(m, '/');
            },
            .Not => {
                stack_push(m, value.init_bool(is_falsey(stack_pop(m))));
            },
            .Negate => {
                if (!value.is_number(peek(m, 0))) {
                    // runtime_error(m, "Operand must be a number.", .{});
                    return Interpret_Error.Runtime_Error;
                }

                stack_push(m, value.init_number(-value.as_number(stack_pop(m))));
            },
            .Print => {
                value.print_value_with_writer(writer, stack_pop(m)) catch return Interpret_Error.Runtime_Error;
                writer.writeByte('\n') catch return Interpret_Error.Runtime_Error;
            },
        }
    }
}

fn read_short(m: *VM) u16 {
    m.ip += 2;
    const hi = @intCast(u16, (m.ip - 2)[0]) << 8;
    const lo = @intCast(u16, (m.ip - 1)[0]);
    return hi | lo;
}

fn read_string(m: *VM) *value.Obj_String {
    const constant = read_constant(m);
    return value.as_string(constant);
}

fn concatenate(m: *VM) !void {
    const b = value.as_string(stack_pop(m));
    const a = value.as_string(stack_pop(m));

    const length = a.chars.len + b.chars.len;
    const chars = try m.alloc.alloc(u8, length);
    @memcpy(chars[0..a.chars.len], a.chars);
    @memcpy(chars[a.chars.len..length], b.chars);

    const result = try value.take_string(m, chars);
    stack_push(m, value.init_obj(&result.obj));
}

fn is_falsey(v: value.Value) bool {
    return value.is_nil(v) or (value.is_bool(v) and !value.as_bool(v));
}

fn binary_op(m: *VM, comptime op: u8) !void {
    if (!value.is_number(peek(m, 0)) or !value.is_number(peek(m, 1))) {
        // runtime_error(m, "Operands must be numbers.", .{});
        return Interpret_Error.Runtime_Error;
    }

    const b = value.as_number(stack_pop(m));
    const a = value.as_number(stack_pop(m));
    const result = switch (op) {
        '+' => value.init_number(a + b),
        '-' => value.init_number(a - b),
        '*' => value.init_number(a * b),
        '/' => value.init_number(a / b),
        '<' => value.init_bool(a < b),
        '>' => value.init_bool(a > b),
        else => @compileError("invalid binary operator"),
    };
    stack_push(m, result);
}

fn peek(m: *VM, distance: usize) value.Value {
    return (m.stack_top - 1 - distance)[0];
}

fn runtime_error(m: *VM, comptime format: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print(format ++ "\n", args) catch {};
    const instruction = @intFromPtr(m.ip) - @intFromPtr(m.chunk.code.items.ptr) - 1;
    const line = m.chunk.lines.items[instruction];
    stderr.print("[line {d}] in script\n", .{line}) catch {};
    reset_stack(m);
}

fn read_byte(m: *VM) u8 {
    // TODO(sezoka): add bounds check maybe
    const byte = m.ip[0];
    m.ip += 1;
    return byte;
}

fn read_byte_code(m: *VM) chunk.Op_Code {
    return @enumFromInt(chunk.Op_Code, read_byte(m));
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
