const std = @import("std");

pub const Scanner = struct {
    start: []const u8,
    current: usize,
    line: u32,
};

pub const Token = struct {
    kind: Token_Kind,
    lexeme: []const u8,
    line: u32,
};

const token_kinds_map = std.ComptimeStringMap(Token_Kind, .{
    .{ "and", .And },
    .{ "class", .Class },
    .{ "else", .Else },
    .{ "if", .If },
    .{ "nil", .Nil },
    .{ "or", .Or },
    .{ "print", .Print },
    .{ "return", .Return },
    .{ "super", .Super },
    .{ "var", .Var },
    .{ "whlie", .While },
});

pub fn create(src: []const u8) Scanner {
    return .{
        .start = src,
        .current = 0,
        .line = 1,
    };
}

pub fn scan_token(s: *Scanner) Token {
    skip_whitespace(s);
    s.start = s.start[s.current..];
    s.current = 0;

    if (is_at_end(s.*)) return make_token(s, .Eof);

    const c = advance(s);

    if (std.ascii.isDigit(c)) return read_number(s);
    if (is_alpha(c)) return read_ident(s);

    switch (c) {
        '(' => return make_token(s, .Left_Paren),
        ')' => return make_token(s, .Right_Paren),
        '{' => return make_token(s, .Left_Brace),
        '}' => return make_token(s, .Right_Brace),
        ';' => return make_token(s, .Semicolon),
        ',' => return make_token(s, .Comma),
        '.' => return make_token(s, .Dot),
        '-' => return make_token(s, .Minus),
        '+' => return make_token(s, .Plus),
        '/' => return make_token(s, .Slash),
        '*' => return make_token(s, .Star),
        '!' => return make_token(s, if (match(s, '=')) .Bang_Equal else .Bang),
        '=' => return make_token(s, if (match(s, '=')) .Equal_Equal else .Equal),
        '<' => return make_token(s, if (match(s, '=')) .Less_Equal else .Less),
        '>' => return make_token(s, if (match(s, '=')) .Greater_Equal else .Greater),
        '"' => return read_string(s),
        else => unreachable,
    }

    return error_token(s, "Unexpected character.");
}

fn is_alpha(c: u8) bool {
    return 'a' <= c and c <= 'z' or 'A' <= c and c <= 'Z' or c == '_';
}

fn read_ident(s: *Scanner) Token {
    while (is_alpha(peek(s.*)) or std.ascii.isDigit(peek(s.*))) _ = advance(s);
    return make_token(s, ident_kind(s));
}

fn ident_kind(s: *Scanner) Token_Kind {
    return token_kinds_map.get(s.start[0..s.current]) orelse .Identifier;
}

fn read_number(s: *Scanner) Token {
    while (std.ascii.isDigit(peek(s.*))) _ = advance(s);

    if (peek(s.*) == '.' and std.ascii.isDigit(peek_next(s.*))) {
        _ = advance(s);

        while (std.ascii.isDigit(peek(s.*))) _ = advance(s);
    }

    return make_token(s, .Number);
}

fn read_string(s: *Scanner) Token {
    while (peek(s.*) != '"' and !is_at_end(s.*)) {
        if (peek(s.*) != '\n') s.line += 1;
        _ = advance(s);
    }

    if (is_at_end(s.*)) return error_token(s, "Unterminated string");

    _ = advance(s);
    return make_token(s, .String);
}

fn skip_whitespace(s: *Scanner) void {
    while (true) {
        const c = peek(s.*);
        switch (c) {
            ' ', '\r', '\t' => _ = advance(s),
            '/' => {
                if (peek_next(s.*) == '/') {
                    while (peek(s.*) != '\n' and !is_at_end(s.*)) _ = advance(s);
                } else {
                    return;
                }
            },
            '\n' => {
                s.line += 1;
                _ = advance(s);
            },
            else => return,
        }
    }
}

fn peek_next(s: Scanner) u8 {
    if (is_at_end(s)) return 0;
    return s.start[s.current + 1];
}

fn peek(s: Scanner) u8 {
    if (is_at_end(s)) return 0;
    return s.start[s.current];
}

fn match(s: *Scanner, expected: u8) bool {
    if (is_at_end(s.*)) return false;
    if (s.current != expected) return false;
    s.current += 1;
    return true;
}

pub fn advance(s: *Scanner) u8 {
    s.current += 1;
    return s.start[s.current - 1];
}

fn make_token(s: *Scanner, kind: Token_Kind) Token {
    return .{
        .kind = kind,
        .lexeme = s.start[0..s.current],
        .line = s.line,
    };
}

fn error_token(s: *Scanner, msg: []const u8) Token {
    return .{
        .kind = .Error,
        .lexeme = msg,
        .line = s.line,
    };
}

fn is_at_end(s: Scanner) bool {
    return s.start.len <= s.current;
}

pub const Token_Kind = enum {
    // Single-character tokens.
    Left_Paren,
    Right_Paren,
    Left_Brace,
    Right_Brace,
    Comma,
    Dot,
    Minus,
    Plus,
    Semicolon,
    Slash,
    Star,
    // One or two character tokens.
    Bang,
    Bang_Equal,
    Equal,
    Equal_Equal,
    Greater,
    Greater_Equal,
    Less,
    Less_Equal,
    // Literals.
    Identifier,
    String,
    Number,
    // Keywords.
    And,
    Class,
    Else,
    False,
    For,
    Fun,
    If,
    Nil,
    Or,
    Print,
    Return,
    Super,
    This,
    True,
    Var,
    While,

    Error,
    Eof,
};
