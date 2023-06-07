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
    HadError,
};

const Function_Kind = enum {
    function,
    script,
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
const u8_count = std.math.maxInt(u8) + 1;

const Local = struct {
    name: Token,
    depth: i32,
};

const Compiler = struct {
    function: *value.Obj_Function,
    kind: Function_Kind,

    locals: [u8_count]Local,
    local_count: i32,
    scope_depth: i32,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, kind: Function_Kind) !Self {
        return .{
            .locals = undefined,
            .local_count = 0,
            .scope_depth = 0,
            .kind = kind,
            .function = try value.Obj_Function.init(alloc),
        };
    }
};

pub const Parser = struct {
    scanner: Scanner,
    previous: Token,
    current: Token,
    had_error: bool,
    panic_mode: bool,

    compiler: *Compiler,

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
            .had_error = false,
            .panic_mode = false,
            .compiler = undefined,

            .vm = vm,
            .alloc = vm.alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn compile(self: *Self, source: []const u8) !*value.Obj_Function {
        self.scanner = Scanner.init(source);
        var compiler = try Compiler.init(self.alloc, .script);
        self.init_compiler(&compiler);

        self.advance();

        while (!self.match(.eof)) {
            try self.declaration();
        }

        // var line: usize = 0;
        // while (true) {
        //     const token = self.scanner.next();
        //     if (token.line != line) {
        //         std.debug.print("{d:4} ", .{token.line});
        //         line = token.line;
        //     } else {
        //         std.debug.print("   | ", .{});
        //     }
        //     std.debug.print("{d:2} '{s}'\n", .{ token.line, token.lexeme });

        //     if (token.kind == .eof) break;
        // }

        const function = try self.end_compiler();
        if (self.had_error) {
            return Compile_Error.HadError;
        } else {
            return function;
        }
    }

    fn current_chunk(self: *Self) *Chunk {
        return self.compiler.function.chunk;
    }

    fn init_compiler(self: *Self, compiler: *Compiler) void {
        compiler.local_count = 0;
        compiler.scope_depth = 0;
        self.compiler = compiler;

        const local = &self.compiler.locals[@intCast(usize, self.compiler.local_count)];
        self.compiler.local_count += 1;
        local.depth = 0;
        local.name = "erer";
        local.name.lexeme = "";
    }

    fn parse_variable(self: *Self, comptime error_message: []const u8) !u8 {
        self.consume(.identifier, error_message);

        self.declare_variable();
        if (0 < self.compiler.scope_depth) return 0;

        return self.identifier_constant(self.previous);
    }

    fn identifier_constant(self: *Self, name: Token) !u8 {
        const new_string = try value.Obj_String.init(name.lexeme, true, false, self.vm);
        const str_object = @ptrCast(*value.Obj, new_string);
        self.vm.obj_push(str_object);
        const val = Value.init_obj(str_object);
        const idx = try self.current_chunk().add_constant(val);
        return @intCast(u8, idx);
    }

    fn add_local(self: *Self, name: Token) void {
        if (self.compiler.local_count == u8_count) {
            self.error_("Too many local variables in function.");
            return;
        }

        const local = &self.compiler.locals[@intCast(usize, self.compiler.local_count)];
        self.compiler.local_count += 1;
        local.name = name;
        local.depth = -1;
    }

    fn declare_variable(self: *Self) void {
        if (self.compiler.scope_depth == 0) return;
        const name = self.previous;

        var i = self.compiler.local_count - 1;
        while (0 <= i) : (i -= 1) {
            const local = self.compiler.locals[@intCast(usize, i)];
            if (local.depth != -1 and local.depth < self.compiler.scope_depth) {
                break;
            }

            if (identifiers_equal(name, local.name)) {
                self.error_("Already a variable with this name in this scope.");
            }
        }

        self.add_local(name);
    }

    fn define_variable(self: *Self, global: u8) !void {
        std.debug.print("H!@!#!@#@!#\n", .{});
        if (0 < self.compiler.scope_depth) {
            self.mark_initialized();
            return;
        }

        return self.emit_bytes(Op_Code.op_define_global.byte(), global);
    }

    fn mark_initialized(self: *Self) void {
        self.compiler.locals[@intCast(usize, self.compiler.local_count - 1)].depth = self.compiler.scope_depth;
    }

    fn var_declaration(self: *Self) !void {
        const global = try self.parse_variable("Expect variable name.");

        if (self.match(.equal)) {
            try self.expression();
        } else {
            try self.emit_byte(Op_Code.op_nil.byte());
        }

        self.consume(.semicolon, "Expect ';' after variable declaration.");

        return self.define_variable(global);
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
        } else if (self.match(.for_)) {
            try self.for_statement();
        } else if (self.match(.if_)) {
            try self.if_statement();
        } else if (self.match(.while_)) {
            try self.while_statement();
        } else if (self.match(.left_brace)) {
            self.begin_scope();
            try self.block();
            self.end_scope();
        } else {
            try self.expression_statement();
        }
    }

    fn for_statement(self: *Self) Compile_Error!void {
        self.begin_scope();
        self.consume(.left_paren, "Expect '(' after 'for'.");

        if (self.match(.semicolon)) {} else if (self.match(.var_)) {
            try self.var_declaration();
        } else {
            try self.expression_statement();
        }

        var loop_start: usize = self.current_chunk().code.items.len;
        var exit_jump: usize = std.math.maxInt(usize);

        if (!self.match(.semicolon)) {
            try self.expression();
            self.consume(.semicolon, "Expect ';' after loop condition.");

            exit_jump = try self.emit_jump(.op_jump_if_false);
            try self.emit_byte(Op_Code.op_pop.byte());
        }

        if (!self.match(.right_paren)) {
            const body_jump = try self.emit_jump(.op_jump);
            const increment_start = self.current_chunk().code.items.len;
            try self.expression();
            try self.emit_byte(Op_Code.op_pop.byte());
            self.consume(.right_paren, "Expect ')' after for clauses.");

            try self.emit_loop(loop_start);
            loop_start = increment_start;
            self.patch_jump(body_jump);
        }

        try self.statement();
        try self.emit_loop(loop_start);

        if (exit_jump != std.math.maxInt(usize)) {
            self.patch_jump(exit_jump);
            try self.emit_byte(Op_Code.op_pop.byte());
        }

        self.end_scope();
    }

    fn while_statement(self: *Self) Compile_Error!void {
        const loop_start = self.current_chunk().code.items.len;
        self.consume(.left_paren, "Expect '(' after 'while'.");
        try self.expression();
        self.consume(.right_paren, "Expect ')' after condition.");

        const exit_jump = try self.emit_jump(.op_jump_if_false);
        try self.emit_byte(Op_Code.op_pop.byte());
        try self.statement();
        try self.emit_loop(loop_start);

        self.patch_jump(exit_jump);
        try self.emit_byte(Op_Code.op_pop.byte());
    }

    fn emit_loop(self: *Self, loop_start: usize) !void {
        try self.emit_byte(Op_Code.op_loop.byte());

        const offset = self.current_chunk().code.items.len - loop_start + 2;
        if (std.math.maxInt(u16) < offset) self.error_("Loop body too large.");

        try self.emit_byte(@intCast(u8, (offset >> 8) & 0xff));
        try self.emit_byte(@intCast(u8, offset & 0xff));
    }

    fn if_statement(self: *Self) Compile_Error!void {
        self.consume(.left_paren, "Expect '(' after 'if'.");
        try self.expression();
        self.consume(.right_paren, "Expect ')' after condition.");

        const then_jump = try self.emit_jump(.op_jump_if_false);
        try self.emit_byte(Op_Code.op_pop.byte());
        try self.statement();

        const else_jump = try self.emit_jump(.op_jump);

        self.patch_jump(then_jump);
        try self.emit_byte(Op_Code.op_pop.byte());

        if (self.match(.else_)) try self.statement();
        self.patch_jump(else_jump);
    }

    fn emit_jump(self: *Self, instruction: Op_Code) !usize {
        try self.emit_byte(instruction.byte());
        try self.emit_byte(0xff);
        try self.emit_byte(0xff);
        return self.current_chunk().code.items.len - 2;
    }

    fn patch_jump(self: *Self, offset: usize) void {
        const jump = self.current_chunk().code.items.len - offset - 2;

        if (std.math.maxInt(u16) < jump) {
            self.error_("Too much code to jump over.");
        }

        self.current_chunk().code.items[offset] = @intCast(u8, (jump >> 8)) & 0xff;
        self.current_chunk().code.items[offset + 1] = @intCast(u8, jump & 0xff);
    }

    fn block(self: *Self) Compile_Error!void {
        while (!self.check(.right_brace) and !self.check(.eof)) {
            try self.declaration();
        }

        self.consume(.right_brace, "Expect '}' after block.");
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
        try self.current_chunk().append_byte(byte, @intCast(u16, self.previous.line));
    }

    fn emit_bytes(self: *Self, byte_1: u8, byte_2: u8) !void {
        try self.current_chunk().append_byte(byte_1, @intCast(u16, self.previous.line));
        try self.current_chunk().append_byte(byte_2, @intCast(u16, self.previous.line));
    }

    fn end_compiler(self: *Self) !*value.Obj_Function {
        try self.emit_return();
        const function = self.compiler.function;

        if (builtin.mode == .Debug) {
            if (!self.had_error) {
                try debug.disassemble_chunk(self.current_chunk(), if (function.name != null) function.name.?.as_slice() else "<script>");
            }
        }

        return function;
    }

    fn begin_scope(self: *Self) void {
        self.compiler.scope_depth += 1;
    }

    fn end_scope(self: *Self) void {
        self.compiler.scope_depth -= 1;
    }

    fn expression(self: *Self) !void {
        try self.parse_precedence(.assignment);
    }

    fn number(self: *Self, _: bool) !void {
        const val = std.fmt.parseFloat(f32, self.previous.lexeme) catch unreachable;
        self.current_chunk().append_constant(Value.init_num(val), self.previous.line) catch unreachable;
    }

    fn string(self: *Self, _: bool) !void {
        const src_str = self.previous.lexeme[1 .. self.previous.lexeme.len - 1];
        const dst_str = try self.alloc.alloc(u8, src_str.len);
        @memcpy(dst_str, src_str);

        const str_obj = try value.Obj_String.init(dst_str, false, true, self.vm);
        const obj_ptr = @ptrCast(*value.Obj, str_obj);
        self.vm.obj_push(obj_ptr);

        try self.current_chunk().append_constant(Value.init_obj(obj_ptr), self.previous.line);
    }

    fn variable(self: *Self, can_assign: bool) !void {
        return self.named_variable(self.previous, can_assign);
    }

    fn named_variable(self: *Self, name: Token, can_assign: bool) !void {
        var get_op: u8 = undefined;
        var set_op: u8 = undefined;
        var arg = self.resolve_local(self.compiler, name);
        if (arg != -1) {
            get_op = Op_Code.op_get_local.byte();
            set_op = Op_Code.op_set_local.byte();
        } else {
            arg = try self.identifier_constant(name);
            get_op = Op_Code.op_get_global.byte();
            set_op = Op_Code.op_set_global.byte();
        }

        if (can_assign and self.match(.equal)) {
            try self.expression();
            return self.emit_bytes(set_op, @intCast(u8, arg));
        } else {
            return self.emit_bytes(get_op, @intCast(u8, arg));
        }
    }

    fn resolve_local(self: *Self, compiler: *Compiler, name: Token) i32 {
        var i = compiler.local_count - 1;
        while (0 <= i) : (i -= 1) {
            const local = &compiler.locals[@intCast(usize, i)];
            if (identifiers_equal(name, local.name)) {
                if (local.depth == -1) {
                    self.error_("Can't read local variable in its own initializer.");
                    break;
                }
                return i;
            }
        }
        return -1;
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

    fn and_(self: *Self, _: bool) !void {
        const end_jump = try self.emit_jump(.op_jump_if_false);

        try self.emit_byte(Op_Code.op_pop.byte());
        try self.parse_precedence(.and_);

        self.patch_jump(end_jump);
    }

    fn or_(self: *Self, _: bool) !void {
        const else_jump = try self.emit_jump(.op_jump_if_false);
        const end_jump = try self.emit_jump(.op_jump);

        self.patch_jump(else_jump);
        try self.emit_byte(Op_Code.op_pop.byte());

        try self.parse_precedence(.or_);
        self.patch_jump(end_jump);
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
            .and_ => make_rule(null, and_, .and_),
            .class => make_rule(null, null, .none),
            .else_ => make_rule(null, null, .none),
            .false_ => make_rule(literal, null, .none),
            .for_ => make_rule(null, null, .none),
            .fun => make_rule(null, null, .none),
            .if_ => make_rule(null, null, .none),
            .nil => make_rule(literal, null, .none),
            .or_ => make_rule(null, or_, .or_),
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

fn identifiers_equal(a: Token, b: Token) bool {
    return std.mem.eql(u8, a.lexeme, b.lexeme);
}
