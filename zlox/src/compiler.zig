const std = @import("std");
const log = std.log;
const builtin = @import("builtin");
const debug = @import("./debug.zig");
const Scanner = @import("./scanner.zig").Scanner;
const Value = @import("./value.zig").Value;
const Token = @import("./scanner.zig").Token;
const Token_Kind = @import("./scanner.zig").Token_Kind;
const Chunk = @import("./chunk.zig").Chunk;
const Op_Code = @import("./chunk.zig").Op_Code;

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
    alloc: std.mem.Allocator,

    const Self = @This();

    const Parse_Fn = ?*const fn (self: *Self) void;

    const Parse_Rule = struct {
        prefix: Parse_Fn,
        infix: Parse_Fn,
        precedence: Precedence,
    };

    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .previous = undefined,
            .current = undefined,
            .scanner = undefined,
            .compiling_chunk = undefined,
            .had_error = false,
            .panic_mode = false,

            .alloc = alloc,
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
        self.previous = self.current;
        self.expression();
        self.consume(.eof, "Expect end of expression");
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

    fn expression(self: *Self) void {
        self.parse_precedence(.assignment);
    }

    fn number(self: *Self) void {
        const value = std.fmt.parseFloat(f32, self.previous.lexeme) catch unreachable;
        self.compiling_chunk.append_constant(Value.init_num(value), self.previous.line) catch unreachable;
    }

    fn unary(self: *Self) void {
        const operator_kind = self.previous.kind;
        self.parse_precedence(.unary);

        const maybe_error = switch (operator_kind) {
            .bang => self.emit_byte(Op_Code.op_not.byte()),
            .minus => self.emit_byte(Op_Code.op_negate.byte()),
            else => unreachable,
        };

        maybe_error catch @panic("Hello\n");
    }

    fn binary(self: *Self) void {
        const operator_kind = self.previous.kind;
        const rule = get_rule(operator_kind);
        self.parse_precedence(@intToEnum(Precedence, rule.precedence.id() + 1));

        const maybe_error = switch (operator_kind) {
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

        maybe_error catch @panic("Just buy more memory\n");
    }

    fn literal(self: *Self) void {
        const maybe_error = switch (self.previous.kind) {
            .false_ => self.emit_byte(Op_Code.op_false.byte()),
            .nil => self.emit_byte(Op_Code.op_nil.byte()),
            .true_ => self.emit_byte(Op_Code.op_true.byte()),
            else => unreachable,
        };

        maybe_error catch @panic("That's very sad :(\n");
    }

    fn parse_precedence(self: *Self, precedence: Precedence) void {
        _ = self.advance();
        const prefix_rule = get_rule(self.previous.kind).prefix orelse {
            self.error_("Expect expression.");
            return;
        };

        prefix_rule(self);

        while (self.current.kind != .eof and precedence.id() <= get_rule(self.current.kind).precedence.id()) {
            _ = self.advance();
            const infix_rule = get_rule(self.previous.kind).infix orelse {
                self.error_("Expect expression");
                std.debug.print("{any}\n", .{self.previous.kind});
                return;
            };
            infix_rule(self);
        }
    }

    fn grouping(self: *Self) void {
        self.expression();
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
            .identifier => make_rule(null, null, .none),
            .string => make_rule(null, null, .none),
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