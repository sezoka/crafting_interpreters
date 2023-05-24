const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Chunk = @import("./chunk.zig").Chunk;
const Op_Code = @import("./chunk.zig").Op_Code;
const value = @import("./value.zig");
const Value = value.Value;
const debug = @import("./debug.zig");
const Scanner = @import("./scanner.zig").Scanner;
const compiler = @import("./compiler.zig");

pub const Interpret_Error = error{
    Compile_Error,
    Runtime_Error,
};

const stack_max = 256;

const Stack = std.BoundedArray(Value, stack_max);

pub const VM = struct {
    chunk: Chunk,
    ip: [*]u8,
    stack: Stack,
    alloc: Allocator,

    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        var vm = VM{
            .chunk = undefined,
            .ip = undefined,
            .stack = Stack.init(0) catch unreachable,
            .alloc = alloc,
        };
        return vm;
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    fn stack_reset(self: *Self) void {
        self.stack_top = @ptrCast([*]Value, &self.stack.items[0]);
    }

    fn stack_push(self: *Self, val: Value) Interpret_Error!void {
        self.stack.append(val) catch return Interpret_Error.Runtime_Error;
    }

    fn stack_pop(self: *Self) Interpret_Error!Value {
        return self.stack.popOrNull() orelse return Interpret_Error.Runtime_Error;
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
        const b = try self.stack_pop();
        const a = try self.stack_pop();
        const result = switch (op) {
            '+' => a + b,
            '-' => a - b,
            '*' => a * b,
            '/' => a / b,
            else => unreachable,
        };
        try self.stack_push(result);
    }

    pub fn interpret(self: *Self, source: []const u8) Interpret_Error!void {
        _ = self;
        compiler.compile(source);
    }

    fn run(self: *Self) Interpret_Error!void {
        while (true) {
            if (builtin.mode == .Debug) {
                std.debug.print("          ", .{});
                var i = 0;
                while (i < self.stack.len) : (i += 1) {
                    std.debug.print("[ ", .{});
                    value.print(self.stack.buffer[i]);
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
                    const val = &self.stack.buffer[self.stack.len - 1];
                    val.* = -(val.*);
                },
                Op_Code.op_return.byte() => {
                    const val = try self.stack_pop();
                    value.print(val);
                    std.debug.print("\n", .{});
                    return;
                },
                Op_Code.op_add.byte() => try self.binary_op('+'),
                Op_Code.op_subtract.byte() => try self.binary_op('-'),
                Op_Code.op_multiply.byte() => try self.binary_op('*'),
                Op_Code.op_divide.byte() => try self.binary_op('/'),
                else => return Interpret_Error.Runtime_Error,
            }
        }
    }
};
