const std = @import("std");
const log = std.log;
const builtin = @import("builtin");
const debug = @import("./debug.zig");
const Scanner = @import("./scanner.zig").Scanner;
const value = @import("./value.zig");
const Value = value.Value;
const Token = @import("./scanner.zig").Token;
const Token_Kind = @import("./scanner.zig").Token_Kind;
const Chunk = @import("./chunk.zig").Chunk;
const Op_Code = @import("./chunk.zig").Op_Code;
const VM = @import("./vm.zig").VM;

const Compile_Error = error{
    OutOfMemory,
};

const Precedence = enum(u8) {
    none,
    assignment,
    or_,
    and_,
    equality,
    comparison,
    term,
    factor,
    unary,
    call,
    primary,

    const Self = @This();

    pub fn id(self: Self) u8 {
        return @enumToInt(self);
    }
};

pub const Compiler = struct {
    scanner: Scanner,
    previous: Token,
    current: Token,
    compiling_chunk: Chunk,
    had_error: bool,
    panic_mode: bool,

    vm: *VM,
    alloc: std.mem.Allocator,

    const Self = @This();

    const Parse_Fn = ?*const fn (self: *Self, can_assign: bool) Compile_Error!void;

    const Parse_Rule = struct {
        prefix: Parse_Fn,
        infix: Parse_Fn,
        precedence: Precedence,
    };

    pub fn init(vm: *VM) Self {
        return .{
            .previous = undefined,
            .current = undefined,
            .scanner = undefined,
            .compiling_chunk = undefined,
            .had_error = false,
            .panic_mode = false,

            .vm = vm,
            .alloc = vm.alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn compile(self: *Self, source: []const u8) !Chunk {
        self.compiling_chunk = Chunk.init(self.alloc);

        self.scanner = Scanner.init(source);
        var line: usize = 0;

        self.advance();

        while (!self.match(.eof)) {
            try self.declaration();
        }

        try self.end_compiler();

        while (true) {
            const token = self.scanner.next();
            if (token.line != line) {
                std.debug.print("{d:4} ", .{token.line});
                line = token.line;
            } else {
                std.debug.print("   | ", .{});
            }
            std.debug.print("{d:2} '{s}'\n", .{ token.line, token.lexeme });

            if (token.kind == .eof) break;
        }

        return self.compiling_chunk;
    }

    fn parse_variable(self: *Self, comptime error_message: []const u8) !u8 {
        self.consume(.identifier, error_message);
        return self.identifier_constant(&self.previous);
    }

    fn identifier_constant(self: *Self, name: *Token) !u8 {
        const new_string = try value.Obj_String.init(name.lexeme, true, false, self.vm);
        const str_object = @ptrCast(*value.Obj, new_string);
        self.vm.obj_push(str_object);
        const val = Value.init_obj(str_object);
        const idx = try self.compiling_chunk.add_constant(val);
        return @intCast(u8, idx);
    }

    fn defind_variable(self: *Self, global: u8) !void {
        return self.emit_bytes(Op_Code.op_define_global.byte(), global);
    }

    fn var_declaration(self: *Self) !void {
        const global = try self.parse_variable("Expect variable name.");

        if (self.match(.equal)) {
            try self.expression();
        } else {
            try self.emit_byte(Op_Code.op_nil.byte());
        }

        self.consume(.semicolon, "Expect ';' after variable declaration.");

        return self.defind_variable(global);
    }

    fn declaration(self: *Self) !void {
        if (self.match(.var_)) {
            try self.var_declaration();
        } else {
            try self.statement();
        }

        if (self.panic_mode) self.synchronize();
    }

    fn synchronize(self: *Self) void {
        self.panic_mode = false;

        while (self.current.kind != .eof) {
            if (self.previous.kind == .semicolon) return;
            switch (self.current.kind) {
                .class, .fun, .var_, .for_, .if_, .while_, .print, .return_ => return,
                else => {},
            }
        }

        self.advance();
    }

    fn statement(self: *Self) !void {
        if (self.match(.print)) {
            return self.print_statment();
        } else {
            try self.expression_statement();
        }
    }

    fn expression_statement(self: *Self) !void {
        try self.expression();
        self.consume(.semicolon, "Expect ';' after expression.");
        try self.emit_byte(Op_Code.op_pop.byte());
    }

    fn check(self: *Self, kind: Token_Kind) bool {
        return self.current.kind == kind;
    }

    fn print_statment(self: *Self) !void {
        try self.expression();
        self.consume(.semicolon, "Expect ';' after value.");
        return self.emit_byte(Op_Code.op_print.byte());
    }

    fn match(self: *Self, kind: Token_Kind) bool {
        if (!self.check(kind)) return false;
        self.advance();
        return true;
    }

    fn advance(self: *Self) void {
        self.previous = self.current;

        while (true) {
            self.current = self.scanner.next();
            if (self.current.kind != .error_) break;

            self.error_at_current(self.current.lexeme);
        }
    }

    fn consume(self: *Self, kind: Token_Kind, message: []const u8) void {
        if (self.current.kind == kind) {
            self.advance();
            return;
        }

        self.error_at_current(message);
    }

    fn emit_byte(self: *Self, byte: u8) !void {
        try self.compiling_chunk.append_byte(byte, @intCast(u16, self.previous.line));
    }

    fn emit_bytes(self: *Self, byte_1: u8, byte_2: u8) !void {
        try self.compiling_chunk.append_byte(byte_1, @intCast(u16, self.previous.line));
        try self.compiling_chunk.append_byte(byte_2, @intCast(u16, self.previous.line));
    }

    fn end_compiler(self: *Self) !void {
        try self.emit_return();
        if (builtin.mode == .Debug) {
            if (!self.had_error) {
                try debug.disassemble_chunk(self.compiling_chunk, "code");
            }
        }
    }

    fn expression(self: *Self) !void {
        try self.parse_precedence(.assignment);
    }

    fn number(self: *Self, _: bool) !void {
        const val = std.fmt.parseFloat(f32, self.previous.lexeme) catch unreachable;
        self.compiling_chunk.append_constant(Value.init_num(val), self.previous.line) catch unreachable;
    }

    fn string(self: *Self, _: bool) !void {
        const src_str = self.previous.lexeme[1 .. self.previous.lexeme.len - 1];
        const dst_str = try self.alloc.alloc(u8, src_str.len);
        @memcpy(dst_str, src_str);

        const str_obj = try value.Obj_String.init(dst_str, false, true, self.vm);
        const obj_ptr = @ptrCast(*value.Obj, str_obj);
        self.vm.obj_push(obj_ptr);

        try self.compiling_chunk.append_constant(Value.init_obj(obj_ptr), self.previous.line);
    }

    fn variable(self: *Self, can_assign: bool) !void {
        return self.named_variable(&self.previous, can_assign);
    }

    fn named_variable(self: *Self, name: *Token, can_assign: bool) !void {
        const arg = try self.identifier_constant(name);

        if (can_assign and self.match(.equal)) {
            try self.expression();
            return self.emit_bytes(Op_Code.op_set_global.byte(), arg);
        } else {
            return self.emit_bytes(Op_Code.op_get_global.byte(), arg);
        }
    }

    fn unary(self: *Self, _: bool) !void {
        const operator_kind = self.previous.kind;
        try self.parse_precedence(.unary);

        try switch (operator_kind) {
            .bang => self.emit_byte(Op_Code.op_not.byte()),
            .minus => self.emit_byte(Op_Code.op_negate.byte()),
            else => unreachable,
        };
    }

    fn binary(self: *Self, _: bool) !void {
        const operator_kind = self.previous.kind;
        const rule = get_rule(operator_kind);
        try self.parse_precedence(@intToEnum(Precedence, rule.precedence.id() + 1));

        try switch (operator_kind) {
            .bang_equal => self.emit_bytes(Op_Code.op_equal.byte(), Op_Code.op_not.byte()),
            .equal_equal => self.emit_byte(Op_Code.op_equal.byte()),
            .greater => self.emit_byte(Op_Code.op_greater.byte()),
            .greater_equal => self.emit_bytes(Op_Code.op_less.byte(), Op_Code.op_not.byte()),
            .less => self.emit_byte(Op_Code.op_less.byte()),
            .less_equal => self.emit_byte(Op_Code.op_greater.byte()),
            .plus => self.emit_byte(Op_Code.op_add.byte()),
            .minus => self.emit_byte(Op_Code.op_subtract.byte()),
            .star => self.emit_byte(Op_Code.op_multiply.byte()),
            .slash => self.emit_byte(Op_Code.op_divide.byte()),
            else => unreachable,
        };
    }

    fn literal(self: *Self, _: bool) !void {
        try switch (self.previous.kind) {
            .false_ => self.emit_byte(Op_Code.op_false.byte()),
            .nil => self.emit_byte(Op_Code.op_nil.byte()),
            .true_ => self.emit_byte(Op_Code.op_true.byte()),
            else => unreachable,
        };
    }

    fn parse_precedence(self: *Self, precedence: Precedence) !void {
        _ = self.advance();
        const prefix_rule = get_rule(self.previous.kind).prefix orelse {
            self.error_("Expect expression.");
            return;
        };

        const can_assign = precedence.id() <= Precedence.assignment.id();
        try prefix_rule(self, can_assign);

        while (self.current.kind != .eof and precedence.id() <= get_rule(self.current.kind).precedence.id()) {
            _ = self.advance();
            const infix_rule = get_rule(self.previous.kind).infix orelse {
                self.error_("Expect expression");
                std.debug.print("{any}\n", .{self.previous.kind});
                return;
            };
            try infix_rule(self, can_assign);
        }

        if (can_assign and self.match(.equal)) {
            self.error_("Invalid assignment target.");
        }
    }

    fn grouping(self: *Self, _: bool) !void {
        try self.expression();
        self.consume(.right_paren, "Expect ')' after expression.");
    }

    fn emit_return(self: *Self) !void {
        try self.emit_byte(Op_Code.op_return.byte());
    }

    fn error_at_current(self: *Self, message: []const u8) void {
        self.error_at(self.current, message);
    }

    fn error_(self: *Self, message: []const u8) void {
        self.error_at(self.previous, message);
    }

    fn error_at(self: *Self, token: Token, message: []const u8) void {
        if (self.panic_mode) return;
        self.panic_mode = true;
        const err_writer = std.io.getStdErr().writer();

        err_writer.print("[line {d}] Error", .{token.line}) catch {};

        if (token.kind == .eof) {
            err_writer.writeAll(" at end. ") catch {};
        } else if (token.kind == .error_) {} else {
            err_writer.print(" at '{s}'. ", .{token.lexeme}) catch {};
        }

        err_writer.print("{s}\n", .{message}) catch {};
        self.had_error = true;
    }

    fn get_rule(kind: Token_Kind) Parse_Rule {
        return switch (kind) {
            .left_paren => make_rule(grouping, null, .none),
            .right_paren => make_rule(null, null, .none),
            .left_brace => make_rule(null, null, .none),
            .right_brace => make_rule(null, null, .none),
            .comma => make_rule(null, null, .none),
            .dot => make_rule(null, null, .none),
            .minus => make_rule(unary, binary, .term),
            .plus => make_rule(null, binary, .term),
            .semicolon => make_rule(null, null, .none),
            .slash => make_rule(null, binary, .factor),
            .star => make_rule(null, binary, .factor),
            .bang => make_rule(unary, null, .none),
            .bang_equal => make_rule(null, binary, .equality),
            .equal => make_rule(null, null, .none),
            .equal_equal => make_rule(null, binary, .equality),
            .greater => make_rule(null, binary, .comparison),
            .greater_equal => make_rule(null, binary, .comparison),
            .less => make_rule(null, binary, .comparison),
            .less_equal => make_rule(null, binary, .comparison),
            .identifier => make_rule(variable, null, .none),
            .string => make_rule(string, null, .none),
            .number => make_rule(number, null, .none),
            .and_ => make_rule(null, null, .none),
            .class => make_rule(null, null, .none),
            .else_ => make_rule(null, null, .none),
            .false_ => make_rule(literal, null, .none),
            .for_ => make_rule(null, null, .none),
            .fun => make_rule(null, null, .none),
            .if_ => make_rule(null, null, .none),
            .nil => make_rule(literal, null, .none),
            .or_ => make_rule(null, null, .none),
            .print => make_rule(null, null, .none),
            .return_ => make_rule(null, null, .none),
            .super => make_rule(null, null, .none),
            .this => make_rule(null, null, .none),
            .true_ => make_rule(literal, null, .none),
            .var_ => make_rule(null, null, .none),
            .while_ => make_rule(null, null, .none),
            .error_ => make_rule(null, null, .none),
            .eof => make_rule(null, null, .none),
        };
    }

    fn make_rule(comptime prefix: Parse_Fn, comptime infix: Parse_Fn, comptime precedence: Precedence) Parse_Rule {
        return .{ .prefix = prefix, .infix = infix, .precedence = precedence };
    }
};
