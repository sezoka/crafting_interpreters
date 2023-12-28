const std = @import("std");
const scanner = @import("scanner.zig");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const debug = @import("debug.zig");
const Chunk = chunk.Chunk;
const Op_Code = chunk.Op_Code;
const Token = scanner.Token;
const Token_Kind = scanner.Token_Kind;
const Scanner = scanner.Scanner;
const Value = value.Value;

pub const Parser = struct {
    current: Token,
    previous: Token,
};

pub const Compiler = struct {
    parser: Parser,
    scaner: Scanner,
    chunk: *Chunk,
    had_error: bool,
    panic_mode: bool,
};

const Parse_Rule = struct {
    prefix: Parse_Fn,
    infix: Parse_Fn,
    precedence: Precedence,
};

const Parse_Fn = ?*const fn (c: *Compiler) Parse_Rule_Result;

const Parse_Rule_Error = error{OutOfMemory};

const Parse_Rule_Result = Parse_Rule_Error!void;

const Precedence = enum {
    None,
    Assignment, // =
    Or, // OR
    And, // AND
    Equality, // == !=
    Comparison, // < > <= >=
    Term, // + -
    Factor, // * /
    Unary, // ! -
    Call, // . ()
    Primary,
};

pub fn compile(source: []const u8, ch: *Chunk) !bool {
    var compiler = Compiler{
        .parser = .{
            .current = undefined,
            .previous = undefined,
        },
        .scaner = scanner.create(source),
        .chunk = ch,
        .had_error = false,
        .panic_mode = false,
    };

    advance(&compiler);
    try expression(&compiler);
    consume(&compiler, .Eof, "Expect end of expression.");

    try end_compiler(&compiler);
    return !compiler.had_error;
}

fn expression(c: *Compiler) !void {
    try parse_precedence(c, .Assignment);
}

fn number(c: *Compiler) Parse_Rule_Result {
    const val = std.fmt.parseFloat(f64, c.parser.previous.lexeme) catch unreachable;
    try emit_constant(c, value.from_float(val));
}

fn literal(c: *Compiler) Parse_Rule_Result {
    try switch (c.parser.previous.kind) {
        .False => emit_byte(c, to_byte(.False)),
        .Nil => emit_byte(c, to_byte(.Nil)),
        .True => emit_byte(c, to_byte(.True)),
        else => return,
    };
}

fn grouping(c: *Compiler) Parse_Rule_Result {
    try expression(c);
    consume(c, .Right_Paren, "Expect ')' after expression.");
}

fn unary(c: *Compiler) Parse_Rule_Result {
    const op_kind = c.parser.previous.kind;
    try parse_precedence(c, .Unary);

    switch (op_kind) {
        .Bang => try emit_byte(c, to_byte(.Not)),
        .Minus => try emit_byte(c, to_byte(.Negate)),
        else => unreachable,
    }
}

fn binary(c: *Compiler) Parse_Rule_Result {
    const op_kind = c.parser.previous.kind;
    const rule = get_rule(op_kind);
    try parse_precedence(c, @enumFromInt(@intFromEnum(rule.precedence) + 1));

    try switch (op_kind) {
        .Bang_Equal => emit_bytes(c, to_byte(.Equal), to_byte(.Not)),
        .Equal_Equal => emit_byte(c, to_byte(.Equal)),
        .Greater => emit_byte(c, to_byte(.Greater)),
        .Greater_Equal => emit_bytes(c, to_byte(.Less), to_byte(.Not)),
        .Less => emit_byte(c, to_byte(.Less)),
        .Less_Equal => emit_bytes(c, to_byte(.Greater), to_byte(.Not)),
        .Plus => emit_byte(c, to_byte(.Add)),
        .Minus => emit_byte(c, to_byte(.Subtract)),
        .Star => emit_byte(c, to_byte(.Multiply)),
        .Slash => emit_byte(c, to_byte(.Divide)),
        else => return,
    };
}

fn parse_precedence(c: *Compiler, prec: Precedence) !void {
    advance(c);
    const prefix_rule = get_rule(c.parser.previous.kind).prefix;
    if (prefix_rule == null) {
        error_at_prev(c, "Expect expression.");
        return;
    }

    try prefix_rule.?(c);

    while (@intFromEnum(prec) <= @intFromEnum(get_rule(c.parser.current.kind).precedence)) {
        advance(c);
        const infix_rule = get_rule(c.parser.previous.kind).infix;
        try infix_rule.?(c);
    }
}

fn get_rule(kind: Token_Kind) *Parse_Rule {
    return &rules[@intFromEnum(kind)];
}

fn emit_constant(c: *Compiler, val: Value) !void {
    try emit_bytes(c, to_byte(.Constant), try make_constant(c, val));
}

fn make_constant(c: *Compiler, val: Value) !u8 {
    const constant = try chunk.add_constant(current_chunk(c), val);
    if (std.math.maxInt(u8) < constant) {
        error_at_prev(c, "Too many constants in one chunk.");
        return 0;
    }

    return constant;
}

fn end_compiler(c: *Compiler) !void {
    try emit_return(c);
    if (debug.IS_DEBUG and !c.had_error) {
        debug.disassemble_chunk(current_chunk(c).*, "code");
    }
}

fn emit_return(c: *Compiler) !void {
    try emit_byte(c, to_byte(.Return));
}

fn emit_bytes(c: *Compiler, b1: u8, b2: u8) !void {
    try emit_byte(c, b1);
    try emit_byte(c, b2);
}

fn advance(c: *Compiler) void {
    c.parser.previous = c.parser.current;

    while (true) {
        c.parser.current = scanner.scan_token(&c.scaner);
        if (c.parser.current.kind != .Error) break;

        error_at_current(c, c.parser.current.lexeme);
    }
}

fn consume(c: *Compiler, kind: Token_Kind, msg: []const u8) void {
    if (c.parser.current.kind == kind) {
        advance(c);
        return;
    }

    error_at_current(c, msg);
}

fn current_chunk(c: *Compiler) *Chunk {
    return c.chunk;
}

fn emit_byte(c: *Compiler, byte: u8) !void {
    try chunk.write_byte(current_chunk(c), byte, c.parser.previous.line);
}

fn error_at_current(c: *Compiler, msg: []const u8) void {
    error_at(c, &c.parser.current, msg);
}

fn error_at_prev(c: *Compiler, msg: []const u8) void {
    error_at(c, &c.parser.previous, msg);
}

fn error_at(c: *Compiler, tok: *Token, msg: []const u8) void {
    if (c.panic_mode) return;
    std.debug.print("[line {d}] Error", .{tok.line});

    if (tok.kind == .Eof) {
        std.debug.print(" at end", .{});
    } else if (tok.kind == .Error) {} else {
        std.debug.print(" at '{s}'", .{tok.lexeme});
    }

    std.debug.print(": {s}\n", .{msg});
    c.had_error = true;
}

fn to_byte(e: Op_Code) u8 {
    return @intFromEnum(e);
}

const rules: []Parse_Rule = blk: {
    var rls: [40]Parse_Rule = undefined;
    rls[@intFromEnum(Token_Kind.Left_Paren)] = parse_rule(grouping, null, .None);
    rls[@intFromEnum(Token_Kind.Right_Paren)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Left_Brace)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Right_Brace)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Comma)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Dot)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Minus)] = parse_rule(unary, binary, .Term);
    rls[@intFromEnum(Token_Kind.Plus)] = parse_rule(null, binary, .Term);
    rls[@intFromEnum(Token_Kind.Semicolon)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Slash)] = parse_rule(null, binary, .Factor);
    rls[@intFromEnum(Token_Kind.Star)] = parse_rule(null, binary, .Factor);
    rls[@intFromEnum(Token_Kind.Bang)] = parse_rule(unary, null, .None);
    rls[@intFromEnum(Token_Kind.Bang_Equal)] = parse_rule(null, binary, .Equality);
    rls[@intFromEnum(Token_Kind.Equal)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Equal_Equal)] = parse_rule(null, binary, .Equality);
    rls[@intFromEnum(Token_Kind.Greater)] = parse_rule(null, binary, .Comparison);
    rls[@intFromEnum(Token_Kind.Greater_Equal)] = parse_rule(null, binary, .Comparison);
    rls[@intFromEnum(Token_Kind.Less)] = parse_rule(null, binary, .Comparison);
    rls[@intFromEnum(Token_Kind.Less_Equal)] = parse_rule(null, binary, .Comparison);
    rls[@intFromEnum(Token_Kind.Identifier)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.String)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Number)] = parse_rule(number, null, .None);
    rls[@intFromEnum(Token_Kind.And)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Class)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Else)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.False)] = parse_rule(literal, null, .None);
    rls[@intFromEnum(Token_Kind.For)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Fun)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.If)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Nil)] = parse_rule(literal, null, .None);
    rls[@intFromEnum(Token_Kind.Or)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Print)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Return)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Super)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.This)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.True)] = parse_rule(literal, null, .None);
    rls[@intFromEnum(Token_Kind.Var)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.While)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Error)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Eof)] = parse_rule(null, null, .None);
    break :blk &rls;
};

fn parse_rule(comptime prefix: Parse_Fn, comptime infix: Parse_Fn, comptime prec: Precedence) Parse_Rule {
    return .{ .prefix = prefix, .infix = infix, .precedence = prec };
}
