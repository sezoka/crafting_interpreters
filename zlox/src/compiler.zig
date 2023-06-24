const std = @import("std");
const builtin = @import("builtin");
const debug = @import("debug.zig");
const chunk = @import("chunk.zig");
const scanner = @import("scanner.zig");
const value = @import("value.zig");
const vm = @import("vm.zig");

const Parser = struct {
    current: scanner.Token,
    previous: scanner.Token,
    panic_mode: bool,
    had_error: bool,
    scanner: *scanner.Scanner,
    compiling_chunk: *chunk.Chunk,
    vm: *vm.VM,
};

const Precedence = enum {
    None,
    Assignment,
    Or,
    And,
    Equality,
    Comparison,
    Term,
    Factor,
    Unary,
    Call,
    Primary,
};

const Parse_Rule = struct {
    prefix: ?*const Parse_Fn = null,
    infix: ?*const Parse_Fn = null,
    precedence: Precedence = .None,
};

const Parse_Fn_Error = error{ OutOfMemory, TooManyConstants };

const Parse_Fn = fn (p: *Parser, can_assign: bool) Parse_Fn_Error!void;

fn init_parser(m: *vm.VM, s: *scanner.Scanner, ch: *chunk.Chunk) Parser {
    return .{
        .current = undefined,
        .previous = undefined,
        .had_error = false,
        .panic_mode = false,
        .scanner = s,
        .compiling_chunk = ch,
        .vm = m,
    };
}

pub fn compile(m: *vm.VM, source: []const u8) !chunk.Chunk {
    var ch = chunk.init_chunk(m.alloc);
    errdefer chunk.deinit_chunk(&ch);

    var s = scanner.init_scanner(source);
    var parser = init_parser(m, &s, &ch);
    advance(&parser);

    while (!match(&parser, .Eof)) {
        try declaration(&parser);
    }

    try end_compiler(&parser);

    if (parser.had_error) {
        return error.ParserHadError;
    }

    return ch;
}

fn declaration(p: *Parser) !void {
    if (match(p, .Var)) {
        try var_declaration(p);
    } else {
        try statement(p);
    }
    if (p.panic_mode) synchronize(p);
}

fn var_declaration(p: *Parser) !void {
    const global = try parse_variable(p, "Expect variable name.");

    if (match(p, .Equal)) {
        try expression(p);
    } else {
        try emit_byte(p, @intFromEnum(chunk.Op_Code.Nil));
    }

    consume(p, .Semicolon, "Expect ';' after variable declaration.");

    try define_variable(p, global);
}

fn parse_variable(p: *Parser, error_message: []const u8) !u8 {
    consume(p, .Identifier, error_message);
    return identifier_constant(p, &p.previous);
}

fn identifier_constant(p: *Parser, name: *scanner.Token) !u8 {
    const str = try value.copy_string(p.vm, name.literal);
    return make_constant(p, value.init_obj(&str.obj));
}

fn define_variable(p: *Parser, global: u8) !void {
    try emit_bytes(p, @intFromEnum(chunk.Op_Code.Define_Global), global);
}

fn synchronize(p: *Parser) void {
    p.panic_mode = false;

    while (p.current.kind != .Eof) {
        if (p.previous.kind == .Semicolon) return;
        switch (p.current.kind) {
            .Class,
            .Fun,
            .Var,
            .For,
            .If,
            .While,
            .Print,
            .Return,
            => return,
            else => advance(p),
        }
    }
}

fn statement(p: *Parser) !void {
    if (match(p, .Print)) {
        try print_statement(p);
    } else {
        try expression_statement(p);
    }
}

fn expression_statement(p: *Parser) !void {
    try expression(p);
    consume(p, .Semicolon, "Expect ';' after expression.");
    try emit_byte(p, @intFromEnum(chunk.Op_Code.Pop));
}

fn match(p: *Parser, kind: scanner.Token_Kind) bool {
    if (!check(p, kind)) return false;
    advance(p);
    return true;
}

fn check(p: *Parser, kind: scanner.Token_Kind) bool {
    return p.current.kind == kind;
}

fn print_statement(p: *Parser) !void {
    try expression(p);
    consume(p, .Semicolon, "Expect ';' after value.");
    try emit_byte(p, @intFromEnum(chunk.Op_Code.Print));
}

fn expression(p: *Parser) !void {
    try parse_precedence(p, .Assignment);
}

fn string(p: *Parser, _: bool) !void {
    const copied_string = try value.copy_string(p.vm, p.previous.literal[1 .. p.previous.literal.len - 1]);
    const string_obj = value.init_obj(&copied_string.obj);
    try emit_constant(p, string_obj);
}

fn grouping(p: *Parser, _: bool) Parse_Fn_Error!void {
    try expression(p);
    consume(p, .Right_Paren, "Expect ')' after expression.");
}

fn unary(p: *Parser, _: bool) !void {
    const operator_kind = p.previous.kind;

    try parse_precedence(p, .Unary);

    switch (operator_kind) {
        .Bang => try emit_byte(p, @intFromEnum(chunk.Op_Code.Not)),
        .Minus => try emit_byte(p, @intFromEnum(chunk.Op_Code.Negate)),
        else => return,
    }
}

fn binary(p: *Parser, _: bool) !void {
    const operator_kind = p.previous.kind;
    const rule = get_rule(operator_kind);
    try parse_precedence(p, @enumFromInt(Precedence, @intFromEnum(rule.precedence) + 1));

    switch (operator_kind) {
        .Bang_Equal => try emit_bytes(p, @intFromEnum(chunk.Op_Code.Equal), @intFromEnum(chunk.Op_Code.Not)),
        .Equal_Equal => try emit_byte(p, @intFromEnum(chunk.Op_Code.Equal)),
        .Greater => try emit_byte(p, @intFromEnum(chunk.Op_Code.Greater)),
        .Greater_Equal => try emit_bytes(p, @intFromEnum(chunk.Op_Code.Less), @intFromEnum(chunk.Op_Code.Not)),
        .Less => try emit_byte(p, @intFromEnum(chunk.Op_Code.Less)),
        .Less_Equal => try emit_bytes(p, @intFromEnum(chunk.Op_Code.Greater), @intFromEnum(chunk.Op_Code.Not)),
        .Plus => try emit_byte(p, @intFromEnum(chunk.Op_Code.Add)),
        .Minus => try emit_byte(p, @intFromEnum(chunk.Op_Code.Subtract)),
        .Star => try emit_byte(p, @intFromEnum(chunk.Op_Code.Multiply)),
        .Slash => try emit_byte(p, @intFromEnum(chunk.Op_Code.Divide)),
        else => return,
    }
}

fn parse_precedence(p: *Parser, precedence: Precedence) !void {
    advance(p);
    const prefix_rule = get_rule(p.previous.kind).prefix;
    if (prefix_rule == null) {
        error_(p, "Expect expression");
        return;
    }

    const can_assign = @intFromEnum(precedence) <= @intFromEnum(Precedence.Assignment);
    try prefix_rule.?(p, can_assign);

    while (@intFromEnum(precedence) <= @intFromEnum(get_rule(p.current.kind).precedence)) {
        advance(p);
        const infix_rule = get_rule(p.previous.kind).infix;
        try infix_rule.?(p, can_assign);
    }

    if (can_assign and match(p, .Equal)) {
        return error_(p, "Invalid assignment target.");
    }
}

fn number(p: *Parser, _: bool) Parse_Fn_Error!void {
    var val = std.fmt.parseFloat(f32, p.previous.literal) catch unreachable;
    try emit_constant(p, value.init_number(val));
}

fn emit_constant(p: *Parser, val: value.Value) !void {
    const constant = try make_constant(p, val);
    try emit_bytes(p, @intFromEnum(chunk.Op_Code.Constant), constant);
}

fn make_constant(p: *Parser, val: value.Value) !u8 {
    const constant = try chunk.add_constant(current_chunk(p), val);
    if (std.math.maxInt(u8) < constant) {
        error_(p, "Too many constants in one chunk.");
        return error.TooManyConstants;
    }

    return @intCast(u8, constant);
}

fn end_compiler(p: *Parser) !void {
    try emit_return(p);
    if (builtin.mode == .Debug) {
        if (!p.had_error) {
            debug.disassemble_chunk(current_chunk(p).*, "code");
        }
    }
}

fn emit_return(p: *Parser) !void {
    try emit_byte(p, @intFromEnum(chunk.Op_Code.Return));
}

fn emit_bytes(p: *Parser, byte1: u8, byte2: u8) !void {
    try emit_byte(p, byte1);
    try emit_byte(p, byte2);
}

fn emit_byte(p: *Parser, byte: u8) !void {
    try chunk.append_byte(current_chunk(p), byte, p.previous.line);
}

fn current_chunk(p: *Parser) *chunk.Chunk {
    return p.compiling_chunk;
}

fn consume(p: *Parser, kind: scanner.Token_Kind, message: []const u8) void {
    if (p.current.kind == kind) {
        advance(p);
        return;
    }

    error_at_current(p, message);
}

fn advance(p: *Parser) void {
    p.previous = p.current;

    while (true) {
        p.current = scanner.scan_token(p.scanner);
        if (p.current.kind != .Error) break;

        error_at_current(p, p.current.literal);
    }
}

fn error_at_current(p: *Parser, message: []const u8) void {
    error_at(p, p.current, message);
}

fn error_(p: *Parser, message: []const u8) void {
    error_at(p, p.previous, message);
}

fn error_at(p: *Parser, token: scanner.Token, message: []const u8) void {
    if (p.panic_mode) return;
    p.panic_mode = true;

    const stderr = std.io.getStdErr().writer();

    stderr.print("[line {d}] Error", .{token.line}) catch {};

    if (token.kind == .Eof) {
        stderr.print(" at end", .{}) catch {};
    } else if (token.kind == .Error) {
        //
    } else {
        stderr.print(" at '{s}'", .{token.literal}) catch {};
    }

    stderr.print(": {s}\n", .{message}) catch {};
    p.had_error = true;
}

fn literal(p: *Parser, _: bool) Parse_Fn_Error!void {
    switch (p.previous.kind) {
        .True => try emit_byte(p, @intFromEnum(chunk.Op_Code.True)),
        .False => try emit_byte(p, @intFromEnum(chunk.Op_Code.False)),
        .Nil => try emit_byte(p, @intFromEnum(chunk.Op_Code.Nil)),
        else => return,
    }
}

fn variable(p: *Parser, can_assign: bool) Parse_Fn_Error!void {
    try named_variable(p, &p.previous, can_assign);
}

fn named_variable(p: *Parser, name: *scanner.Token, can_assign: bool) Parse_Fn_Error!void {
    const arg = try identifier_constant(p, name);

    if (can_assign and match(p, .Equal)) {
        try expression(p);
        try emit_bytes(p, @intFromEnum(chunk.Op_Code.Set_Global), arg);
    } else {
        try emit_bytes(p, @intFromEnum(chunk.Op_Code.Get_Global), arg);
    }
}

fn get_rule(kind: scanner.Token_Kind) *const Parse_Rule {
    return &@as(Parse_Rule, switch (kind) {
        .Left_Paren => .{ .prefix = grouping },
        .Right_Paren => .{},
        .Left_Brace => .{},
        .Right_Brace => .{},
        .Comma => .{},
        .Dot => .{},
        .Minus => .{ .prefix = unary, .infix = binary, .precedence = .Term },
        .Plus => .{ .infix = binary, .precedence = .Term },
        .Semicolon => .{},
        .Slash => .{ .infix = binary, .precedence = .Factor },
        .Star => .{ .infix = binary, .precedence = .Factor },
        .Bang => .{ .prefix = unary },
        .Bang_Equal => .{ .infix = binary, .precedence = .Equality },
        .Equal => .{},
        .Equal_Equal => .{ .infix = binary, .precedence = .Equality },
        .Greater => .{ .infix = binary, .precedence = .Comparison },
        .Greater_Equal => .{ .infix = binary, .precedence = .Comparison },
        .Less => .{ .infix = binary, .precedence = .Comparison },
        .Less_Equal => .{ .infix = binary, .precedence = .Comparison },
        .Identifier => .{ .prefix = variable },
        .String => .{ .prefix = string },
        .Number => .{ .prefix = number },
        .And => .{},
        .Class => .{},
        .Else => .{},
        .False => .{ .prefix = literal },
        .For => .{},
        .Fun => .{},
        .If => .{},
        .Nil => .{ .prefix = literal },
        .Or => .{},
        .Print => .{},
        .Return => .{},
        .Super => .{},
        .This => .{},
        .True => .{ .prefix = literal },
        .Var => .{},
        .While => .{},
        .Error => .{},
        .Eof => .{},
    });
}
