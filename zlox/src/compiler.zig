const std = @import("std");
const builtin = @import("builtin");
const debug = @import("debug.zig");
const chunk = @import("chunk.zig");
const scanner = @import("scanner.zig");
const value = @import("value.zig");

const Parser = struct {
    current: scanner.Token,
    previous: scanner.Token,
    panic_mode: bool,
    had_error: bool,
    scanner: *scanner.Scanner,
    compiling_chunk: *chunk.Chunk,
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

const Parse_Fn = fn (p: *Parser) Parse_Fn_Error!void;

fn init_parser(s: *scanner.Scanner, ch: *chunk.Chunk) Parser {
    return .{
        .current = undefined,
        .previous = undefined,
        .had_error = false,
        .panic_mode = false,
        .scanner = s,
        .compiling_chunk = ch,
    };
}

pub fn compile(alloc: std.mem.Allocator, source: []const u8) !chunk.Chunk {
    var ch = chunk.init_chunk(alloc);
    errdefer chunk.deinit_chunk(&ch);

    var s = scanner.init_scanner(source);
    var parser = init_parser(&s, &ch);
    advance(&parser);
    try expression(&parser);
    consume(&parser, .Eof, "Expect end of expression");

    try end_compiler(&parser);

    if (parser.had_error) {
        return error.ParserHadError;
    }

    return ch;
}

fn expression(p: *Parser) !void {
    try parse_precedence(p, .Assignment);
}

fn grouping(p: *Parser) Parse_Fn_Error!void {
    try expression(p);
    consume(p, .Right_Paren, "Expect ')' after expression.");
}

fn unary(p: *Parser) !void {
    const operator_kind = p.previous.kind;

    try parse_precedence(p, .Unary);

    switch (operator_kind) {
        .Minus => try emit_byte(p, @enumToInt(chunk.Op_Code.Negate)),
        else => return,
    }
}

fn binary(p: *Parser) !void {
    const operator_kind = p.previous.kind;
    const rule = get_rule(operator_kind);
    try parse_precedence(p, @intToEnum(Precedence, @enumToInt(rule.precedence) + 1));

    switch (operator_kind) {
        .Plus => try emit_byte(p, @enumToInt(chunk.Op_Code.Add)),
        .Minus => try emit_byte(p, @enumToInt(chunk.Op_Code.Subtract)),
        .Star => try emit_byte(p, @enumToInt(chunk.Op_Code.Multiply)),
        .Slash => try emit_byte(p, @enumToInt(chunk.Op_Code.Divide)),
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

    try prefix_rule.?(p);

    while (@enumToInt(precedence) <= @enumToInt(get_rule(p.current.kind).precedence)) {
        advance(p);
        const infix_rule = get_rule(p.previous.kind).infix;
        try infix_rule.?(p);
    }
}

fn number(p: *Parser) Parse_Fn_Error!void {
    var val = std.fmt.parseFloat(f64, p.previous.literal) catch unreachable;
    try emit_constant(p, val);
}

fn emit_constant(p: *Parser, val: value.Value) !void {
    const constant = try make_constant(p, val);
    try emit_bytes(p, @enumToInt(chunk.Op_Code.Constant), constant);
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
    try emit_byte(p, @enumToInt(chunk.Op_Code.Return));
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
        .Bang => .{},
        .Bang_Equal => .{},
        .Equal => .{},
        .Equal_Equal => .{},
        .Greater => .{},
        .Greater_Equal => .{},
        .Less => .{},
        .Less_Equal => .{},
        .Identifier => .{},
        .String => .{},
        .Number => .{ .prefix = number },
        .And => .{},
        .Class => .{},
        .Else => .{},
        .False => .{},
        .For => .{},
        .Fun => .{},
        .If => .{},
        .Nil => .{},
        .Or => .{},
        .Print => .{},
        .Return => .{},
        .Super => .{},
        .This => .{},
        .True => .{},
        .Var => .{},
        .While => .{},
        .Error => .{},
        .Eof => .{},
    });
}
