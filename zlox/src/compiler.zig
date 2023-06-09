const std = @import("std");
const config = @import("config.zig");
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
    compiler: *Compiler,
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

const Compiler = struct {
    function: ?*value.Obj_Function,
    kind: Function_Kind,

    locals: [U8_COUNT]Local,
    local_count: i32,
    scope_depth: i32,
};

const Function_Kind = enum {
    Function,
    Script,
};

const Local = struct {
    name: scanner.Token,
    depth: i32,
};

const Parse_Fn_Error = error{ OutOfMemory, TooManyConstants };

const Compile_Error = error{ OutOfMemory, TooManyConstants };

const Parse_Fn = fn (p: *Parser, can_assign: bool) Parse_Fn_Error!void;

const U8_COUNT = 256;
const U16_MAX = std.math.maxInt(u16);

fn init_parser(m: *vm.VM, s: *scanner.Scanner, ch: *chunk.Chunk, compiler: *Compiler) Parser {
    return .{
        .current = undefined,
        .previous = undefined,
        .had_error = false,
        .panic_mode = false,
        .scanner = s,
        .compiling_chunk = ch,
        .vm = m,
        .compiler = compiler,
    };
}

fn init_compiler(p: *Parser, kind: Function_Kind) Compiler {
    var c = .{
        .function = value.init_function(p.alloc),
        .kind = kind,
        .local_count = 0,
        .scope_depth = 0,
        .locals = [_]Local{.{ .name = undefined, .depth = 0 }} ** 256,
    };

    var local = &p.compiler.locals[p.compiler.locals.len];
    local.depth = 0;
    local.name.literal = "";

    return c;
}

pub fn compile(m: *vm.VM, source: []const u8) !*chunk.Obj_Function {
    var ch = chunk.init_chunk(m.alloc);
    errdefer chunk.deinit_chunk(&ch);

    var s = scanner.init_scanner(source);
    var compiler = init_compiler(m.alloc, .Script);
    var parser = init_parser(m, &s, &ch, &compiler);
    advance(&parser);

    while (!match(&parser, .Eof)) {
        try declaration(&parser);
    }

    const function = try end_compiler(&parser);

    if (parser.had_error) {
        return null;
        // return error.ParserHadError;
    }

    return function;
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

    try declare_variable(p);
    if (0 < p.compiler.scope_depth) return 0;

    return identifier_constant(p, &p.previous);
}

fn declare_variable(p: *Parser) !void {
    if (p.compiler.scope_depth == 0) return;

    const name = &p.previous;

    var i = p.compiler.local_count - 1;
    while (0 <= i) : (i -= 1) {
        const local = &p.compiler.locals[@intCast(usize, i)];
        if (local.depth != -1 and local.depth < p.compiler.scope_depth) {
            break;
        }

        if (identifiers_equal(name, &local.name)) {
            error_(p, "Already a variable with this name if this scope.");
        }
    }

    add_local(p, name.*);
}

fn identifiers_equal(a: *scanner.Token, b: *scanner.Token) bool {
    return std.mem.eql(u8, a.literal, b.literal);
}

fn add_local(p: *Parser, name: scanner.Token) void {
    if (p.compiler.local_count == U8_COUNT) {
        error_(p, "too many local variables in function.");
        return;
    }

    var local = &p.compiler.locals[@intCast(usize, p.compiler.local_count)];
    p.compiler.local_count += 1;
    local.name = name;
    local.depth = -1;
    local.depth = p.compiler.scope_depth;
}

fn identifier_constant(p: *Parser, name: *scanner.Token) !u8 {
    const str = try value.copy_string(p.vm, name.literal);
    return make_constant(p, value.init_obj(&str.obj));
}

fn define_variable(p: *Parser, global: u8) !void {
    if (0 < p.compiler.scope_depth) {
        mark_initialized(p);
        return;
    }

    try emit_bytes(p, @intFromEnum(chunk.Op_Code.Define_Global), global);
}

fn and_(p: *Parser, _: bool) !void {
    const end_jump = try emit_jump(p, .Jump_If_False);

    try emit_byte(p, @intFromEnum(chunk.Op_Code.Pop));
    try parse_precedence(p, .And);

    patch_jump(p, end_jump);
}

fn or_(p: *Parser, _: bool) !void {
    const else_jump = try emit_jump(p, .Jump_If_False);
    const end_jump = try emit_jump(p, .Jump);

    patch_jump(p, else_jump);
    try emit_byte(p, @intFromEnum(chunk.Op_Code.Pop));

    try parse_precedence(p, .Or);
    patch_jump(p, end_jump);
}

fn mark_initialized(p: *Parser) void {
    p.compiler.locals[@intCast(usize, p.compiler.local_count - 1)].depth = p.compiler.scope_depth;
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
    } else if (match(p, .For)) {
        try for_statement(p);
    } else if (match(p, .If)) {
        try if_statement(p);
    } else if (match(p, .While)) {
        try while_statement(p);
    } else if (match(p, .Left_Brace)) {
        begin_scope(p);
        try block(p);
        try end_scope(p);
    } else {
        try expression_statement(p);
    }
}

fn for_statement(p: *Parser) Compile_Error!void {
    begin_scope(p);
    consume(p, .Left_Paren, "Expect '(' after 'for'.");

    if (match(p, .Semicolon)) {
        //
    } else if (match(p, .Var)) {
        try var_declaration(p);
    } else {
        try expression_statement(p);
    }

    var loop_start = @intCast(i32, current_chunk(p).code.items.len);
    var exit_jump: i32 = -1;
    if (!match(p, .Semicolon)) {
        try expression(p);
        consume(p, .Semicolon, "Expect ';' after loop condition.");

        exit_jump = try emit_jump(p, .Jump_If_False);
        try emit_byte(p, @intFromEnum(chunk.Op_Code.Pop));
    }

    if (!match(p, .Right_Paren)) {
        const body_jump = try emit_jump(p, .Jump);
        const increment_start = current_chunk(p).code.items.len;
        try expression(p);
        try emit_byte(p, @intFromEnum(chunk.Op_Code.Pop));
        consume(p, .Right_Paren, "Expect ')' after for clauses.");

        try emit_loop(p, loop_start);
        loop_start = @intCast(i32, increment_start);
        patch_jump(p, body_jump);
    }

    try statement(p);
    try emit_loop(p, loop_start);

    if (exit_jump != -1) {
        patch_jump(p, exit_jump);
        try emit_byte(p, @intFromEnum(chunk.Op_Code.Pop));
    }

    try end_scope(p);
}

fn while_statement(p: *Parser) Compile_Error!void {
    const loop_start = @intCast(i32, current_chunk(p).code.items.len);
    consume(p, .Left_Paren, "Expect '(' after 'while'.");
    try expression(p);
    consume(p, .Right_Paren, "Expecct ')' after condition.");

    const exit_jump = try emit_jump(p, .Jump_If_False);
    try emit_byte(p, @intFromEnum(chunk.Op_Code.Pop));
    try statement(p);
    try emit_loop(p, loop_start);

    patch_jump(p, exit_jump);
    try emit_byte(p, @intFromEnum(chunk.Op_Code.Pop));
}

fn emit_loop(p: *Parser, loop_start: i32) !void {
    try emit_byte(p, @intFromEnum(chunk.Op_Code.Loop));

    const offset = current_chunk(p).code.items.len - @intCast(usize, loop_start) + 2;
    if (U16_MAX < offset) error_(p, "Loop body too large.");

    try emit_byte(p, @intCast(u8, (offset >> 8) & 0xff));
    try emit_byte(p, @intCast(u8, offset & 0xff));
}

fn if_statement(p: *Parser) Compile_Error!void {
    consume(p, .Left_Paren, "Expect '(' after 'if'.");
    try expression(p);
    consume(p, .Right_Paren, "Expect ')' after condition.");

    const then_jump = try emit_jump(p, .Jump_If_False);
    try emit_byte(p, @intFromEnum(chunk.Op_Code.Pop));
    try statement(p);

    const else_jump = try emit_jump(p, .Jump);

    patch_jump(p, then_jump);
    try emit_byte(p, @intFromEnum(chunk.Op_Code.Pop));

    if (match(p, .Else)) try statement(p);
    patch_jump(p, else_jump);
}

fn emit_jump(p: *Parser, instruction: chunk.Op_Code) !i32 {
    try emit_byte(p, @intFromEnum(instruction));
    try emit_byte(p, 0xff);
    try emit_byte(p, 0xff);
    return @intCast(i32, current_chunk(p).code.items.len - 2);
}

fn patch_jump(p: *Parser, offset: i32) void {
    const jump = current_chunk(p).code.items.len - @intCast(usize, offset) - 2;

    if (U16_MAX < jump) {
        error_(p, "Too much code to jump over.");
    }

    current_chunk(p).code.items[@intCast(usize, offset)] = @intCast(u8, (jump >> 8) & 0xff);
    current_chunk(p).code.items[@intCast(usize, offset + 1)] = @intCast(u8, jump & 0xff);
}

fn begin_scope(p: *Parser) void {
    p.compiler.scope_depth += 1;
}

fn end_scope(p: *Parser) !void {
    p.compiler.scope_depth -= 1;

    while (0 < p.compiler.local_count and
        p.compiler.scope_depth < p.compiler.locals[@intCast(usize, p.compiler.local_count - 1)].depth)
    {
        try emit_byte(p, @intFromEnum(chunk.Op_Code.Pop));
        p.compiler.local_count -= 1;
    }
}

fn block(p: *Parser) Compile_Error!void {
    while (!check(p, .Right_Brace) and !check(p, .Eof)) {
        try declaration(p);
    }

    consume(p, .Right_Brace, "Expect '}' after block.");
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

fn end_compiler(p: *Parser) !*value.Obj_Function {
    try emit_return(p);
    const function = p.compiler.function.?;

    if (config.show_debug_info) {
        if (!p.had_error) {
            debug.disassemble_chunk(current_chunk(p).*, if (function.name.len != 0) function.name else "<script>");
        }
    }

    return function;
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
    return p.compiler.function.chunk;
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
    var get_op: u8 = 0;
    var set_op: u8 = 0;

    var arg = resolve_local(p, name);
    if (arg != -1) {
        get_op = @intFromEnum(chunk.Op_Code.Get_Local);
        set_op = @intFromEnum(chunk.Op_Code.Set_Local);
    } else {
        arg = try identifier_constant(p, name);
        get_op = @intFromEnum(chunk.Op_Code.Get_Global);
        set_op = @intFromEnum(chunk.Op_Code.Set_Global);
    }

    const arg_byte = @intCast(u8, arg);

    if (can_assign and match(p, .Equal)) {
        try expression(p);
        try emit_bytes(p, set_op, arg_byte);
    } else {
        try emit_bytes(p, get_op, arg_byte);
    }
}

fn resolve_local(p: *Parser, name: *scanner.Token) i32 {
    const c = p.compiler;
    var i: i32 = c.local_count - 1;
    while (0 <= i) : (i -= 1) {
        const local = &c.locals[@intCast(usize, i)];
        if (identifiers_equal(name, &local.name)) {
            if (local.depth == -1) {
                error_(p, "Can't read local variable in its own initializer.");
            }
            return i;
        }
    }

    return -1;
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
        .And => .{ .infix = and_, .precedence = .And },
        .Class => .{},
        .Else => .{},
        .False => .{ .prefix = literal },
        .For => .{},
        .Fun => .{},
        .If => .{},
        .Nil => .{ .prefix = literal },
        .Or => .{ .infix = or_, .precedence = .Or },
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
