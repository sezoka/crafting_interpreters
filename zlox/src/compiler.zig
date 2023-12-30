const std = @import("std");
const scanner = @import("scanner.zig");
const chunk = @import("chunk.zig");
const value = @import("value.zig");
const object = @import("object.zig");
const debug = @import("debug.zig");
const vm = @import("vm.zig");

const VM = vm.VM;
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

pub const State = struct {
    parser: Parser,
    scaner: Scanner,
    chunk: *Chunk,
    had_error: bool,
    panic_mode: bool,
    current: Compiler,
    vm: *VM,
};

const Compiler = struct {
    locals: [std.math.maxInt(u8) + 1]Local,
    local_cnt: i32,
    score_depth: i32,
};

const Local = struct {
    name: Token,
    depth: i32,
};

const Parse_Rule = struct {
    prefix: Parse_Fn,
    infix: Parse_Fn,
    precedence: Precedence,
};

const Parse_Fn = ?*const fn (s: *State, can_assign: bool) Parse_Rule_Result;

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

pub fn compile(v: *VM, source: []const u8, ch: *Chunk) !bool {
    var state = State{
        .parser = .{
            .current = undefined,
            .previous = undefined,
        },
        .scaner = scanner.create(source),
        .chunk = ch,
        .had_error = false,
        .panic_mode = false,
        .vm = v,
        .current = create_compiler(),
    };

    advance(&state);

    while (!match(&state, .Eof)) {
        try declaration(&state);
    }

    try end_compiler(&state);
    return !state.had_error;
}

fn create_compiler() Compiler {
    return .{
        .local_cnt = 0,
        .score_depth = 0,
        .locals = undefined,
    };
}

fn declaration(s: *State) error{OutOfMemory}!void {
    if (match(s, .Var)) {
        try var_decl(s);
    } else {
        try statement(s);
    }

    if (s.panic_mode) try synchronize(s);
}

fn var_decl(s: *State) !void {
    const global = try parse_variable(s, "Expect variable name.");

    if (match(s, .Equal)) {
        try expression(s);
    } else {
        try emit_byte(s, to_byte(.Nil));
    }
    consume(s, .Semicolon, "Expect ';' after variable declaration.");

    try define_variable(s, global);
}

fn parse_variable(s: *State, error_message: []const u8) !u8 {
    consume(s, .Identifier, error_message);

    try declare_variable(s);
    if (0 < s.current.score_depth) return 0;

    return identifier_constant(s, s.parser.previous);
}

fn identifier_constant(s: *State, name: Token) !u8 {
    return try make_constant(s, value.from_obj(try object.copy_string(s.vm, name.lexeme)));
}

fn define_variable(s: *State, global: u8) !void {
    if (0 < s.current.score_depth) {
        mark_initialized(s);
        return;
    }
    try emit_bytes(s, to_byte(.Define_Global), global);
}

fn mark_initialized(s: *State) void {
    s.current.locals[@intCast(s.current.local_cnt - 1)].depth = s.current.score_depth;
}

fn declare_variable(s: *State) !void {
    if (s.current.score_depth == 0) return;

    const name = &s.parser.previous;

    var i = s.current.local_cnt - 1;
    while (0 <= i) : (i -= 1) {
        var local = &s.current.locals[@intCast(i)];
        if (local.depth != -1 and local.depth < s.current.score_depth) {
            break;
        }

        if (identifiers_equal(name, &local.name)) {
            error_at_prev(s, "Already a variable with this name in this scope.");
        }
    }

    add_local(s, name.*);
}

fn identifiers_equal(a: *const Token, b: *const Token) bool {
    if (a.lexeme.len != b.lexeme.len) return false;
    return std.mem.eql(u8, a.lexeme, b.lexeme);
}

fn add_local(s: *State, name: Token) void {
    if (s.current.local_cnt == std.math.maxInt(u8)) {
        error_at_prev(s, "Too many local variables in function.");
        return;
    }

    var local = &s.current.locals[@intCast(s.current.local_cnt)];
    s.current.local_cnt += 1;
    local.name = name;
    local.depth = -1;
}

fn synchronize(s: *State) !void {
    s.panic_mode = false;

    while (s.parser.current.kind != .Eof) {
        if (s.parser.previous.kind == .Semicolon) return;
        switch (s.parser.current.kind) {
            .Class, .Fun, .Var, .For, .If, .While, .Print, .Return => return,
            else => {},
        }
        advance(s);
    }
}

fn statement(s: *State) error{OutOfMemory}!void {
    if (match(s, .Print)) {
        try print_stmt(s);
    } else if (match(s, .For)) {
        try for_stmt(s);
    } else if (match(s, .If)) {
        try if_stmt(s);
    } else if (match(s, .While)) {
        try while_stmt(s);
    } else if (match(s, .Left_Brace)) {
        try begin_scope(s);
        try block(s);
        try end_scope(s);
    } else {
        try expr_stmt(s);
    }
}

fn for_stmt(s: *State) !void {
    try begin_scope(s);
    consume(s, .Left_Paren, "Expect '(' after 'for'.");
    if (match(s, .Semicolon)) {} else if (match(s, .Var)) {
        try var_decl(s);
    } else {
        try expr_stmt(s);
    }

    var loop_start = current_chunk(s).code.items.len;
    var exit_jump: i32 = -1;
    if (!match(s, .Semicolon)) {
        try expression(s);
        consume(s, .Semicolon, "Expect ';' after loop condition.");

        exit_jump = try emit_jump(s, to_byte(.Jump_If_False));
        try emit_byte(s, to_byte(.Pop));
    }

    if (!match(s, .Right_Paren)) {
        const body_jump = try emit_jump(s, to_byte(.Jump));
        const increment_start = current_chunk(s).code.items.len;
        try expression(s);
        try emit_byte(s, to_byte(.Pop));
        consume(s, .Right_Paren, "Expect ')' after for clasues.");

        try emit_loop(s, loop_start);
        loop_start = increment_start;
        patch_jump(s, body_jump);
    }

    try statement(s);
    try emit_loop(s, loop_start);

    if (exit_jump != -1) {
        patch_jump(s, exit_jump);
        try emit_byte(s, to_byte(.Pop));
    }

    try end_scope(s);
}

fn while_stmt(s: *State) !void {
    const loop_start = s.chunk.code.items.len;
    consume(s, .Left_Paren, "Expect '(' after 'while'.");
    try expression(s);
    consume(s, .Right_Paren, "Expect ')' after condition.");

    const exit_jump = try emit_jump(s, to_byte(.Jump_If_False));
    try emit_byte(s, to_byte(.Pop));
    try statement(s);
    try emit_loop(s, loop_start);

    patch_jump(s, exit_jump);
    try emit_byte(s, to_byte(.Pop));
}

fn emit_loop(s: *State, loop_start: usize) !void {
    try emit_byte(s, to_byte(.Loop));

    const offset = current_chunk(s).code.items.len - loop_start + 2;
    if (std.math.maxInt(u16) < offset) error_at_prev(s, "Loop body too large.");

    try emit_byte(s, @intCast((offset >> 8) & 0xff));
    try emit_byte(s, @intCast(offset & 0xff));
}

fn if_stmt(s: *State) !void {
    consume(s, .Left_Paren, "Expect '(' after 'if'.");
    try expression(s);
    consume(s, .Right_Paren, "Expect ')' after condition.");

    const then_jump = try emit_jump(s, to_byte(.Jump_If_False));
    try emit_byte(s, to_byte(.Pop));
    try statement(s);

    const else_jump = try emit_jump(s, to_byte(.Jump));

    patch_jump(s, then_jump);
    try emit_byte(s, to_byte(.Pop));

    if (match(s, .Else)) try statement(s);
    patch_jump(s, else_jump);
}

fn emit_jump(s: *State, instruction: u8) !i32 {
    try emit_byte(s, instruction);
    try emit_byte(s, 0xff);
    try emit_byte(s, 0xff);
    return @intCast(current_chunk(s).code.items.len - 2);
}

fn patch_jump(s: *State, offset: i32) void {
    const jump = @as(i32, @intCast(current_chunk(s).code.items.len)) - offset - 2;

    if (std.math.maxInt(u16) < jump) {
        error_at_prev(s, "Too much code to jump over.");
    }

    current_chunk(s).code.items[@intCast(offset)] = @intCast((jump >> 8) & 0xff);
    current_chunk(s).code.items[@intCast(offset + 1)] = @intCast(jump & 0xff);
}

fn block(s: *State) !void {
    while (!check(s, .Right_Brace) and !check(s, .Eof)) {
        try declaration(s);
    }

    consume(s, .Right_Brace, "Expect '}}' after block.");
}

fn begin_scope(s: *State) !void {
    s.current.score_depth += 1;
}

fn end_scope(s: *State) !void {
    s.current.score_depth -= 1;

    while ((0 < s.current.local_cnt) and
        (s.current.score_depth < s.current.locals[@intCast(s.current.local_cnt - 1)].depth))
    {
        try emit_byte(s, to_byte(.Pop));
        s.current.local_cnt -= 1;
    }
}

fn expr_stmt(s: *State) !void {
    try expression(s);
    consume(s, .Semicolon, "Expect ';' after expression.");
    try emit_byte(s, to_byte(.Pop));
}

fn match(s: *State, kind: Token_Kind) bool {
    if (!check(s, kind)) return false;
    advance(s);
    return true;
}

fn check(s: *State, kind: Token_Kind) bool {
    return s.parser.current.kind == kind;
}

fn print_stmt(s: *State) !void {
    try expression(s);
    consume(s, .Semicolon, "Expect ';' after value.");
    try emit_byte(s, to_byte(.Print));
}

fn expression(s: *State) !void {
    try parse_precedence(s, .Assignment);
}

fn number(s: *State, can_assign: bool) Parse_Rule_Result {
    _ = can_assign;
    const val = std.fmt.parseFloat(f64, s.parser.previous.lexeme) catch unreachable;
    try emit_constant(s, value.from_float(val));
}

fn literal(s: *State, can_assign: bool) Parse_Rule_Result {
    _ = can_assign;
    try switch (s.parser.previous.kind) {
        .False => emit_byte(s, to_byte(.False)),
        .Nil => emit_byte(s, to_byte(.Nil)),
        .True => emit_byte(s, to_byte(.True)),
        else => return,
    };
}

fn grouping(s: *State, can_assign: bool) Parse_Rule_Result {
    _ = can_assign;
    try expression(s);
    consume(s, .Right_Paren, "Expect ')' after expression.");
}

fn unary(s: *State, can_assign: bool) Parse_Rule_Result {
    _ = can_assign;
    const op_kind = s.parser.previous.kind;
    try parse_precedence(s, .Unary);

    switch (op_kind) {
        .Bang => try emit_byte(s, to_byte(.Not)),
        .Minus => try emit_byte(s, to_byte(.Negate)),
        else => unreachable,
    }
}

fn string(s: *State, can_assign: bool) Parse_Rule_Result {
    _ = can_assign;
    try emit_constant(s, value.from_obj(try object.copy_string(s.vm, s.parser.previous.lexeme[1 .. s.parser.previous.lexeme.len - 1])));
}

fn variable(s: *State, can_assign: bool) Parse_Rule_Result {
    try named_variable(s, s.parser.previous, can_assign);
}

fn named_variable(s: *State, name: Token, can_assign: bool) Parse_Rule_Result {
    var get_op = Op_Code.Get_Local;
    var set_op = Op_Code.Set_Local;
    var arg = resolve_local(s, &s.current, &name);
    if (arg == -1) {
        arg = try identifier_constant(s, name);
        get_op = .Get_Global;
        set_op = .Set_Global;
    }

    if (can_assign and match(s, .Equal)) {
        try expression(s);
        try emit_bytes(s, to_byte(set_op), @intCast(arg));
    } else {
        try emit_bytes(s, to_byte(get_op), @intCast(arg));
    }
}

fn resolve_local(s: *State, compiler: *Compiler, name: *const Token) i32 {
    var i = compiler.local_cnt - 1;
    while (0 <= i) : (i -= 1) {
        const local = &compiler.locals[@intCast(i)];
        if (identifiers_equal(name, &local.name)) {
            if (local.depth == -1) {
                error_at_prev(s, "Can't read local variable in its own initializer.");
            }
            return i;
        }
    }

    return -1;
}

fn or_(s: *State, can_assign: bool) Parse_Rule_Result {
    _ = can_assign;
    const else_jump = try emit_jump(s, to_byte(.Jump_If_False));
    const end_jump = try emit_jump(s, to_byte(.Jump));

    patch_jump(s, else_jump);
    try emit_byte(s, to_byte(.Pop));

    try parse_precedence(s, .Or);
    patch_jump(s, end_jump);
}

fn and_(s: *State, can_assign: bool) Parse_Rule_Result {
    _ = can_assign;
    const end_jump = try emit_jump(s, to_byte(.Jump_If_False));

    try emit_byte(s, to_byte(.Pop));
    try parse_precedence(s, .And);

    patch_jump(s, end_jump);
}

fn binary(s: *State, can_assign: bool) Parse_Rule_Result {
    _ = can_assign;
    const op_kind = s.parser.previous.kind;
    const rule = get_rule(op_kind);
    try parse_precedence(s, @enumFromInt(@intFromEnum(rule.precedence) + 1));

    try switch (op_kind) {
        .Bang_Equal => emit_bytes(s, to_byte(.Equal), to_byte(.Not)),
        .Equal_Equal => emit_byte(s, to_byte(.Equal)),
        .Greater => emit_byte(s, to_byte(.Greater)),
        .Greater_Equal => emit_bytes(s, to_byte(.Less), to_byte(.Not)),
        .Less => emit_byte(s, to_byte(.Less)),
        .Less_Equal => emit_bytes(s, to_byte(.Greater), to_byte(.Not)),
        .Plus => emit_byte(s, to_byte(.Add)),
        .Minus => emit_byte(s, to_byte(.Subtract)),
        .Star => emit_byte(s, to_byte(.Multiply)),
        .Slash => emit_byte(s, to_byte(.Divide)),
        else => return,
    };
}

fn parse_precedence(s: *State, prec: Precedence) !void {
    advance(s);
    const prefix_rule = get_rule(s.parser.previous.kind).prefix;
    if (prefix_rule == null) {
        error_at_prev(s, "Expect expression.");
        return;
    }

    const can_assign = @intFromEnum(prec) <= @intFromEnum(Precedence.Assignment);
    try prefix_rule.?(s, can_assign);

    while (@intFromEnum(prec) <= @intFromEnum(get_rule(s.parser.current.kind).precedence)) {
        advance(s);
        const infix_rule = get_rule(s.parser.previous.kind).infix;
        try infix_rule.?(s, can_assign);
    }

    if (can_assign and match(s, .Equal)) {
        error_at_prev(s, "Invalid assignment target.");
    }
}

fn get_rule(kind: Token_Kind) *Parse_Rule {
    return &rules[@intFromEnum(kind)];
}

fn emit_constant(s: *State, val: Value) !void {
    try emit_bytes(s, to_byte(.Constant), try make_constant(s, val));
}

fn make_constant(s: *State, val: Value) !u8 {
    const constant = try chunk.add_constant(current_chunk(s), val);
    if (std.math.maxInt(u8) < constant) {
        error_at_prev(s, "Too many constants in one chunk.");
        return 0;
    }

    return constant;
}

fn end_compiler(s: *State) !void {
    try emit_return(s);
    if (debug.IS_DEBUG and !s.had_error) {
        debug.disassemble_chunk(current_chunk(s).*, "code");
    }
}

fn emit_return(s: *State) !void {
    try emit_byte(s, to_byte(.Return));
}

fn emit_bytes(s: *State, b1: u8, b2: u8) !void {
    try emit_byte(s, b1);
    try emit_byte(s, b2);
}

fn advance(s: *State) void {
    s.parser.previous = s.parser.current;

    while (true) {
        s.parser.current = scanner.scan_token(&s.scaner);
        if (s.parser.current.kind != .Error) break;

        error_at_current(s, s.parser.current.lexeme);
    }
}

fn consume(s: *State, kind: Token_Kind, msg: []const u8) void {
    if (s.parser.current.kind == kind) {
        advance(s);
        return;
    }

    error_at_current(s, msg);
}

fn current_chunk(s: *State) *Chunk {
    return s.chunk;
}

fn emit_byte(s: *State, byte: u8) !void {
    try chunk.write_byte(current_chunk(s), byte, s.parser.previous.line);
}

fn error_at_current(s: *State, msg: []const u8) void {
    error_at(s, &s.parser.current, msg);
}

fn error_at_prev(s: *State, msg: []const u8) void {
    error_at(s, &s.parser.previous, msg);
}

fn error_at(s: *State, tok: *Token, msg: []const u8) void {
    if (s.panic_mode) return;
    std.debug.print("[line {d}] Error", .{tok.line});

    if (tok.kind == .Eof) {
        std.debug.print(" at end", .{});
    } else if (tok.kind == .Error) {} else {
        std.debug.print(" at '{s}'", .{tok.lexeme});
    }

    std.debug.print(": {s}\n", .{msg});
    s.had_error = true;
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
    rls[@intFromEnum(Token_Kind.Identifier)] = parse_rule(variable, null, .None);
    rls[@intFromEnum(Token_Kind.String)] = parse_rule(string, null, .None);
    rls[@intFromEnum(Token_Kind.Number)] = parse_rule(number, null, .None);
    rls[@intFromEnum(Token_Kind.And)] = parse_rule(null, and_, .And);
    rls[@intFromEnum(Token_Kind.Class)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Else)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.False)] = parse_rule(literal, null, .None);
    rls[@intFromEnum(Token_Kind.For)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Fun)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.If)] = parse_rule(null, null, .None);
    rls[@intFromEnum(Token_Kind.Nil)] = parse_rule(literal, null, .None);
    rls[@intFromEnum(Token_Kind.Or)] = parse_rule(null, or_, .Or);
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
