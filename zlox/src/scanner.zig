const std = @import("std");

pub const Scanner = struct {
    start: [*]const u8,
    current: [*]const u8,
    last: usize,
    line: u32,
};
pub const Token = struct {
    kind: Token_Kind,
    literal: []const u8,
    line: u32,
};

pub fn init_scanner(source: []const u8) Scanner {
    const start = @ptrCast([*]const u8, source.ptr);
    return .{
        .start = start,
        .current = start,
        .last = @intFromPtr(&source[source.len - 1]),
        .line = 1,
    };
}

pub fn scan_token(s: *Scanner) Token {
    skip_whitespace(s);

    s.start = s.current;

    if (is_at_end(s)) return make_token(s, .Eof);

    const c = advance(s);

    if (is_alpha(c)) return identifier(s);
    if (is_digit(c)) return number(s);

    return switch (c) {
        '(' => make_token(s, .Left_Paren),
        ')' => make_token(s, .Right_Paren),
        '{' => make_token(s, .Left_Brace),
        '}' => make_token(s, .Right_Brace),
        ';' => make_token(s, .Semicolon),
        ',' => make_token(s, .Comma),
        '.' => make_token(s, .Dot),
        '-' => make_token(s, .Minus),
        '+' => make_token(s, .Plus),
        '/' => make_token(s, .Slash),
        '*' => make_token(s, .Star),

        '!' => make_token(s, if (match(s, '=')) .Bang_Equal else .Bang),
        '=' => make_token(s, if (match(s, '=')) .Equal_Equal else .Equal),
        '<' => make_token(s, if (match(s, '=')) .Less_Equal else .Less),
        '>' => make_token(s, if (match(s, '=')) .Greater_Equal else .Greater),

        '"' => string(s),

        else => {
            return error_token(s, "Unexpected character.");
        },
    };
}

fn identifier(s: *Scanner) Token {
    while (is_alpha(peek(s)) or is_digit(peek(s))) _ = advance(s);
    return make_token(s, identifier_kind(s));
}

fn identifier_kind(s: *Scanner) Token_Kind {
    return switch (s.start[0]) {
        'a' => check_keyword(s, 1, 2, "nd", .And),
        'c' => check_keyword(s, 1, 4, "lass", .Class),
        'e' => check_keyword(s, 1, 3, "lse", .Else),
        'i' => check_keyword(s, 1, 1, "f", .If),
        'n' => check_keyword(s, 1, 2, "il", .Nil),
        'o' => check_keyword(s, 1, 1, "r", .Or),
        'p' => check_keyword(s, 1, 4, "rint", .Print),
        'r' => check_keyword(s, 1, 5, "eturn", .Return),
        's' => check_keyword(s, 1, 4, "uper", .Super),
        'v' => check_keyword(s, 1, 2, "ar", .Var),
        'w' => check_keyword(s, 1, 4, "hile", .While),
        'f' => {
            if (1 < get_literal_length(s)) {
                return switch (s.start[1]) {
                    'a' => check_keyword(s, 2, 3, "lse", .False),
                    'o' => check_keyword(s, 2, 1, "r", .For),
                    'u' => check_keyword(s, 2, 1, "un", .Fun),
                    else => .Identifier,
                };
            }
            return .Identifier;
        },
        't' => {
            if (1 < get_literal_length(s)) {
                return switch (s.start[1]) {
                    'h' => check_keyword(s, 2, 4, "is", .This),
                    'r' => check_keyword(s, 2, 4, "ue", .True),
                    else => .Identifier,
                };
            }
            return .Identifier;
        },
        else => {
            return .Identifier;
        },
    };
}

fn check_keyword(s: *Scanner, start: usize, length: usize, rest: []const u8, kind: Token_Kind) Token_Kind {
    if (std.mem.eql(u8, rest, s.start[start .. start + length])) {
        return kind;
    }

    return .Identifier;
}

fn is_alpha(c: u8) bool {
    return ('a' <= c and c <= 'z') or ('A' <= c and c <= 'Z') or c == '_';
}

fn number(s: *Scanner) Token {
    while (is_digit((peek(s)))) _ = advance(s);

    if (peek(s) == '.' and is_digit(peek_next(s))) {
        _ = advance(s);

        while (is_digit(peek(s))) _ = advance(s);
    }

    return make_token(s, .Number);
}

fn is_digit(c: u8) bool {
    return '0' <= c and c <= '9';
}

fn string(s: *Scanner) Token {
    while (peek(s) != '"' and !is_at_end(s)) {
        if (peek(s) == '\n') s.line += 1;
        _ = advance(s);
    }

    if (is_at_end(s)) return error_token(s, "Unterminated string.");

    _ = advance(s);
    return make_token(s, .String);
}

fn skip_whitespace(s: *Scanner) void {
    while (true) {
        const c = peek(s);
        switch (c) {
            ' ', '\r', '\t', '\n' => {
                if (c == '\n') s.line += 1;
                _ = advance(s);
            },
            '/' => if (peek_next(s) == '/') {
                while (peek(s) != '\n' and !is_at_end(s)) _ = advance(s);
            } else {
                return;
            },
            else => return,
        }
    }
}

fn peek_next(s: *Scanner) u8 {
    if (is_at_end(s)) return 0;
    return s.current[1];
}

fn peek(s: *Scanner) u8 {
    return s.current[0];
}

fn match(s: *Scanner, expected: u8) bool {
    if (is_at_end(s)) return false;
    if (s.current[0] != expected) return false;
    s.current += 1;
    return true;
}

fn advance(s: *Scanner) u8 {
    const curr = s.current[0];
    s.current += 1;
    return curr;
}

fn is_at_end(s: *Scanner) bool {
    return s.last < @intFromPtr(s.current);
}

fn make_token(s: *Scanner, kind: Token_Kind) Token {
    return .{
        .kind = kind,
        .literal = get_literal(s),
        .line = s.line,
    };
}

fn error_token(s: *Scanner, message: []const u8) Token {
    return .{
        .kind = .Error,
        .literal = message,
        .line = s.line,
    };
}

fn get_literal(s: *Scanner) []const u8 {
    return s.start[0..get_literal_length(s)];
}

fn get_literal_length(s: *Scanner) usize {
    return @intFromPtr(s.current) - @intFromPtr(s.start);
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
