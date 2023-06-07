const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Chunk = @import("./chunk.zig").Chunk;
const Op_Code = @import("./chunk.zig").Op_Code;
const value = @import("./value.zig");
const Value = value.Value;
const debug = @import("./debug.zig");
const Scanner = @import("./scanner.zig").Scanner;
const Parser = @import("./compiler.zig").Parser;

pub const Interpret_Error = error{
    CompileError,
    RuntimeError,
};

const frames_max = 64;
const stack_max = frames_max * 256;

const Stack = std.BoundedArray(Value, stack_max);
const Strings_Set = std.StringHashMap(void);
const Globals_Map = std.StringHashMap(Value);

const Call_Frame = struct {
    function: *value.Obj_Function,
    ip: [*]u8,
    slots: [*]value.Value,
};

pub const VM = struct {
    frames: [frames_max]Call_Frame,
    frame_cnt: u8,
    stack: Stack,
    objects: ?*value.Obj,
    strings: Strings_Set,
    globals: Globals_Map,

    alloc: Allocator,

    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        var vm = VM{
            .frames = undefined,
            .frame_cnt = 0,
            .stack = Stack.init(0) catch unreachable,
            .objects = null,
            .strings = Strings_Set.init(alloc),
            .globals = Globals_Map.init(alloc),

            .alloc = alloc,
        };
        return vm;
    }

    fn globals_free(self: *Self) void {
        self.globals.deinit();
    }

    pub fn deinit(self: *Self) void {
        self.objects_free();
        self.globals_free();
        self.strings_free();
    }

    fn stack_reset(self: *Self) void {
        self.frame_cnt = 0;
    }

    fn stack_push(self: *Self, val: Value) Interpret_Error!void {
        self.stack.append(val) catch return Interpret_Error.RuntimeError;
    }

    fn stack_pop(self: *Self) Interpret_Error!Value {
        return self.stack.popOrNull() orelse return Interpret_Error.RuntimeError;
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
            .function => {
                var function = @ptrCast(*value.Obj_Function, @alignCast(@alignOf(*value.Obj_Function), obj));
                self.alloc.destroy(function.chunk);
                self.alloc.destroy(function);
            },
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
        const frame = &self.frames[self.frame_cnt - 1];
        const val = frame.ip[0];
        frame.ip += 1;
        return val;
    }

    fn read_constant(self: *Self) Value {
        const frame = &self.frames[self.frame_cnt - 1];
        const idx = self.read_byte();
        return frame.function.chunk.constants.items[idx];
    }

    fn read_long_constant(self: *Self) Value {
        const idx_hi = @intCast(u16, self.read_byte());
        const idx_lo = @intCast(u16, self.read_byte());
        const idx = (idx_hi << 8) | idx_lo;
        const frame = &self.frames[self.frame_cnt - 1];
        return frame.function.chunk.constants.items[idx];
    }

    fn binary_op(self: *Self, comptime op: u8) Interpret_Error!void {
        if (!self.peek(0).is_num() or !self.peek(1).is_num()) {
            self.runtime_error("Operands must be numbers.", .{});
            return Interpret_Error.RuntimeError;
        }

        const b = (try self.stack_pop()).kind.number;
        const a = (try self.stack_pop()).kind.number;
        const result = switch (op) {
            '+' => Value.init_num(a + b),
            '-' => Value.init_num(a - b),
            '*' => Value.init_num(a * b),
            '/' => Value.init_num(a / b),
            '<' => Value.init_bool(a < b),
            '>' => Value.init_bool(a > b),
            else => unreachable,
        };
        try self.stack_push(result);
    }

    pub fn interpret(self: *Self, source: []const u8) Interpret_Error!void {
        var compiler = Parser.init(self);
        defer compiler.deinit();

        const function = compiler.compile(source) catch return Interpret_Error.CompileError;
        self.obj_push(@ptrCast(*value.Obj, function));

        var frame = &self.frames[self.frame_cnt];
        self.frame_cnt += 1;
        frame.function = function;
        frame.ip = function.chunk.code.items.ptr;
        frame.slots = @ptrCast([*]value.Value, &self.stack.buffer[0]);

        return self.run();
    }

    fn runtime_error(self: *Self, comptime format: []const u8, args: anytype) void {
        const stderr = std.io.getStdErr();
        const writer = stderr.writer();
        _ = writer.print(format, args) catch {};
        _ = writer.write("\n") catch {};

        const frame = &self.frames[self.frame_cnt - 1];
        const instruction = @ptrToInt(frame.ip) - @ptrToInt(frame.function.chunk.code.items.ptr - 1);
        const line = frame.function.chunk.lines.items[instruction];

        _ = writer.print("[line {d}] in script\n", .{line}) catch {};
        self.stack_reset();
    }

    fn peek(self: *Self, distance: usize) *Value {
        return &self.stack.buffer[self.stack.len - 1 - distance];
    }

    fn concatenate(self: *Self) Interpret_Error!void {
        const b = (try self.stack_pop()).as_string_slice();
        const a = (try self.stack_pop()).as_string_slice();
        const new_str = std.mem.concat(self.alloc, u8, &.{ a, b }) catch return Interpret_Error.RuntimeError;
        const new_obj = value.Obj_String.init(new_str, false, true, self) catch return Interpret_Error.RuntimeError;
        const result = Value.init_obj(@ptrCast(*value.Obj, new_obj));
        self.obj_push(result.kind.obj);
        try self.stack_push(result);
    }

    fn read_string(self: *Self) *value.Obj_String {
        const val = self.read_constant();
        return val.as_string();
    }

    fn read_short(self: *Self) u16 {
        const frame = &self.frames[self.frame_cnt - 1];
        frame.ip += 2;
        return (@intCast(u16, (frame.ip - 2)[0]) << 8) | @intCast(u16, (frame.ip - 1)[0]);
    }

    fn run(self: *Self) Interpret_Error!void {
        var frame = &self.frames[self.frame_cnt - 1];

        const writer = std.io.getStdOut().writer();

        while (true) {
            if (builtin.mode == .Debug) {
                std.debug.print("          ", .{});
                var i: usize = 0;
                while (i < self.stack.len) : (i += 1) {
                    std.debug.print("[ ", .{});
                    self.stack.buffer[i].print();
                    std.debug.print(" ]", .{});
                }
                std.debug.print("\n", .{});

                _ = debug.disassemble_instruction(frame.function.chunk, @ptrToInt(frame.ip) - @ptrToInt(frame.function.chunk.code.items.ptr)) catch return Interpret_Error.RuntimeError;
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
                        return Interpret_Error.RuntimeError;
                    }
                    val.kind.number = -val.kind.number;
                },
                Op_Code.op_print.byte() => {
                    const val = try self.stack_pop();
                    val.print();
                    writer.writeByte('\n') catch {};
                },
                Op_Code.op_jump.byte() => {
                    const offset = self.read_short();
                    frame.ip += offset;
                },
                Op_Code.op_jump_if_false.byte() => {
                    const offset = self.read_short();
                    if (self.peek(0).is_falsey()) frame.ip += offset;
                },
                Op_Code.op_loop.byte() => {
                    const offset = self.read_short();
                    frame.ip -= offset;
                },
                Op_Code.op_return.byte() => {
                    return;
                },
                Op_Code.op_nil.byte() => try self.stack_push(Value.init_nil()),
                Op_Code.op_true.byte() => try self.stack_push(Value.init_bool(true)),
                Op_Code.op_false.byte() => try self.stack_push(Value.init_bool(false)),
                Op_Code.op_pop.byte() => _ = try self.stack_pop(),
                Op_Code.op_get_local.byte() => {
                    const slot = self.read_byte();
                    try self.stack_push(frame.slots[slot]);
                },
                Op_Code.op_get_global.byte() => {
                    const name = self.read_string();
                    const name_str = name.chars[0..name.len];
                    const val = self.globals.get(name_str) orelse {
                        self.runtime_error("Undefined variable '{s}'.", .{name_str});
                        return Interpret_Error.RuntimeError;
                    };
                    try self.stack_push(val);
                },
                Op_Code.op_define_global.byte() => {
                    const name = self.read_string();
                    self.globals.put(name.chars[0..name.len], self.peek(0).*) catch return Interpret_Error.RuntimeError;
                    _ = try self.stack_pop();
                },
                Op_Code.op_set_local.byte() => {
                    const slot = self.read_byte();
                    frame.slots[slot] = self.peek(0).*;
                },
                Op_Code.op_set_global.byte() => {
                    const name = self.read_string();
                    const name_str = name.chars[0..name.len];

                    if (self.globals.contains(name_str)) {
                        const val = self.peek(0).*;
                        self.globals.put(name_str, val) catch return Interpret_Error.RuntimeError;
                    } else {
                        self.runtime_error("Undefined variable '{s}'", .{name_str});
                        return Interpret_Error.RuntimeError;
                    }
                },
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
                        return Interpret_Error.RuntimeError;
                    }
                },
                Op_Code.op_subtract.byte() => try self.binary_op('-'),
                Op_Code.op_multiply.byte() => try self.binary_op('*'),
                Op_Code.op_divide.byte() => try self.binary_op('/'),
                Op_Code.op_not.byte() => {
                    const val = try self.stack_pop();
                    try self.stack_push(Value.init_bool(val.is_falsey()));
                },
                else => return Interpret_Error.RuntimeError,
            }
        }
    }
};
