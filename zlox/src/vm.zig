const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Chunk = @import("./chunk.zig").Chunk;
const Op_Code = @import("./chunk.zig").Op_Code;
const value = @import("./value.zig");
const Value = value.Value;
const debug = @import("./debug.zig");
const Scanner = @import("./scanner.zig").Scanner;
const Compiler = @import("./compiler.zig").Compiler;

pub const Interpret_Error = error{
    Compile_Error,
    Runtime_Error,
};

const stack_max = 256;

const Stack = std.BoundedArray(Value, stack_max);
const Strings_Set = std.StringHashMap(void);

pub const VM = struct {
    chunk: Chunk,
    ip: [*]u8,
    stack: Stack,
    objects: ?*value.Obj,
    strings: Strings_Set,

    alloc: Allocator,

    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        var vm = VM{
            .chunk = undefined,
            .ip = undefined,
            .stack = Stack.init(0) catch unreachable,
            .objects = null,
            .strings = Strings_Set.init(alloc),

            .alloc = alloc,
        };
        return vm;
    }

    pub fn deinit(self: *Self) void {
        self.objects_free();
        self.strings_free();
    }

    fn stack_reset(self: *Self) void {
        self.stack.resize(0) catch @panic("UUUGH\n");
    }

    fn stack_push(self: *Self, val: Value) Interpret_Error!void {
        self.stack.append(val) catch return Interpret_Error.Runtime_Error;
    }

    fn stack_pop(self: *Self) Interpret_Error!Value {
        return self.stack.popOrNull() orelse return Interpret_Error.Runtime_Error;
    }

    pub fn obj_push(self: *Self, obj: *value.Obj) void {
        obj.next = self.objects;
        self.objects = obj;
    }

    fn strings_free(self: *Self) void {
        var iter = self.strings.keyIterator();
        while (iter.next()) |str| {
            self.alloc.free(str.*);
        }
        self.strings.deinit();
    }

    fn obj_free(self: *Self, obj: *value.Obj) void {
        switch (obj.kind) {
            .string => {
                const str = @ptrCast(*value.Obj_String, @alignCast(@alignOf(*value.Obj_String), obj));
                self.alloc.destroy(str);
            },
        }
    }

    fn objects_free(self: *Self) void {
        var obj = self.objects;
        while (obj) |o| {
            const next = o.next;
            self.obj_free(o);
            obj = next;
        }
    }

    fn read_byte(self: *Self) u8 {
        const val = self.ip[0];
        self.ip += 1;
        return val;
    }

    fn read_constant(self: *Self) Value {
        const idx = self.read_byte();
        return self.chunk.constants.items[idx];
    }

    fn read_long_constant(self: *Self) Value {
        const idx_hi = @intCast(u16, self.read_byte());
        const idx_lo = @intCast(u16, self.read_byte());
        const idx = (idx_hi << 8) | idx_lo;
        return self.chunk.constants.items[idx];
    }

    fn binary_op(self: *Self, comptime op: u8) Interpret_Error!void {
        if (!self.peek(0).is_num() or !self.peek(1).is_num()) {
            self.runtime_error("Operands must be numbers.", .{});
            return Interpret_Error.Runtime_Error;
        }

        const b = (try self.stack_pop()).kind.number;
        const a = (try self.stack_pop()).kind.number;
        const result = switch (op) {
            '+' => Value.init_num(a + b),
            '-' => Value.init_num(a - b),
            '*' => Value.init_num(a * b),
            '/' => Value.init_num(a / b),
            '<' => Value.init_bool(a < b),
            '>' => Value.init_bool(a < b),
            else => unreachable,
        };
        try self.stack_push(result);
    }

    pub fn interpret(self: *Self, source: []const u8) Interpret_Error!void {
        var compiler = Compiler.init(self);
        defer compiler.deinit();

        const chunk = compiler.compile(source) catch return Interpret_Error.Compile_Error;
        defer chunk.deinit();

        self.chunk = chunk;
        self.ip = @ptrCast([*]u8, self.chunk.code.items.ptr);

        try self.run();
    }

    fn runtime_error(self: *Self, comptime format: []const u8, args: anytype) void {
        const stderr = std.io.getStdErr();
        const writer = stderr.writer();
        _ = writer.print(format, args) catch {};
        _ = writer.write("\n") catch {};

        const instruction = @ptrToInt(self.ip) - @ptrToInt(self.chunk.code.items.ptr - 1);
        const line = self.chunk.lines.items[instruction];
        _ = writer.print("[line {d}] in script\n", .{line}) catch {};
        self.stack_reset();
    }

    fn peek(self: *Self, distance: usize) *Value {
        return &self.stack.buffer[self.stack.len - 1 - distance];
    }

    fn concatenate(self: *Self) Interpret_Error!void {
        const b = (try self.stack_pop()).as_string_slice();
        const a = (try self.stack_pop()).as_string_slice();
        const new_str = std.mem.concat(self.alloc, u8, &.{ a, b }) catch return Interpret_Error.Runtime_Error;
        const new_obj = value.Obj_String.init(new_str, self) catch return Interpret_Error.Runtime_Error;
        const result = Value.init_obj(@ptrCast(*value.Obj, new_obj));
        self.obj_push(result.kind.obj);
        try self.stack_push(result);
    }

    fn run(self: *Self) Interpret_Error!void {
        if (self.chunk.code.items.len == 0) return;

        while (true) {
            if (builtin.mode == .Debug) {
                std.debug.print("          ", .{});
                var i: usize = 0;
                while (i < self.stack.len) : (i += 1) {
                    std.debug.print("[ ", .{});
                    value.Value.print(self.stack.buffer[i]);
                    std.debug.print(" ]", .{});
                }
                std.debug.print("\n", .{});

                _ = debug.disassemble_instruction(self.chunk, @ptrToInt(self.ip) - @ptrToInt(&self.chunk.code.items[0])) catch return Interpret_Error.Runtime_Error;
            }
            const instruction = self.read_byte();
            switch (instruction) {
                Op_Code.op_constant.byte() => {
                    const constant = self.read_constant();
                    try self.stack_push(constant);
                },
                Op_Code.op_constant_long.byte() => {
                    const constant = self.read_long_constant();
                    try self.stack_push(constant);
                },
                Op_Code.op_negate.byte() => {
                    // const val = &self.stack.buffer[self.stack.len - 1];
                    var val = self.peek(0);
                    if (!(val.*).is_num()) {
                        self.runtime_error("Operand must be a number.", .{});
                        return Interpret_Error.Runtime_Error;
                    }
                    val.kind.number = -val.kind.number;
                },
                Op_Code.op_return.byte() => {
                    const val = try self.stack_pop();
                    val.print();
                    std.debug.print("\n", .{});
                    return;
                },
                Op_Code.op_nil.byte() => try self.stack_push(Value.init_nil()),
                Op_Code.op_true.byte() => try self.stack_push(Value.init_bool(true)),
                Op_Code.op_false.byte() => try self.stack_push(Value.init_bool(false)),
                Op_Code.op_equal.byte() => {
                    const a = try self.stack_pop();
                    const b = try self.stack_pop();
                    try self.stack_push(Value.init_bool(a.equal(b)));
                },
                Op_Code.op_greater.byte() => try self.binary_op('>'),
                Op_Code.op_less.byte() => try self.binary_op('<'),
                Op_Code.op_add.byte() => {
                    if (self.peek(0).is_string() and self.peek(1).is_string()) {
                        try self.concatenate();
                    } else if (self.peek(0).is_num() and self.peek(1).is_num()) {
                        try self.binary_op('+');
                    } else {
                        self.runtime_error("Operands must be two numbers or two strings.", .{});
                        return Interpret_Error.Runtime_Error;
                    }
                },
                Op_Code.op_subtract.byte() => try self.binary_op('-'),
                Op_Code.op_multiply.byte() => try self.binary_op('*'),
                Op_Code.op_divide.byte() => try self.binary_op('/'),
                Op_Code.op_not.byte() => {
                    const val = try self.stack_pop();
                    try self.stack_push(Value.init_bool(val.is_falsey()));
                },
                else => return Interpret_Error.Runtime_Error,
            }
        }
    }
};
