const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;

pub const Token_Kind = enum {
    left_paren,
    right_paren,
    left_brace,
    right_brace,

    comma,
    dot,
    minus,
    plus,
    semicolon,
    slash,
    star,

    bang,
    bang_equal,
    equal,
    equal_equal,
    greater,
    greater_equal,
    less,
    less_equal,

    identifier,
    string,
    number,

    and_,
    class,
    else_,
    false_,
    for_,
    fun,
    if_,
    nil,
    or_,
    print,
    return_,
    super,
    this,
    true,
    var_,
    while_,

    error_,
    eof,
};

pub const Token = struct {
    kind: Token_Kind,
    lexeme: []const u8,
    line: u16,
};

pub const Scanner = struct {
    start: [*]const u8,
    current: [*]const u8,
    line: u16,
    end: usize,

    const Self = @This();

    pub fn init(source: []const u8) Self {
        const start = @ptrCast([*]const u8, source.ptr);
        const end = @ptrToInt(source.ptr + source.len);

        return .{
            .start = start,
            .current = start,
            .line = 1,
            .end = end,
        };
    }

    pub fn next(self: *Self) Token {
        self.skip_whitespace();
        self.start = self.current;

        if (self.is_at_end()) return self.make_token(.eof);

        const c = self.advance();

        if (is_alpha(c)) return self.identifier();
        if (ascii.isDigit(c)) return self.number();

        return switch (c) {
            '(' => self.make_token(.left_paren),
            ')' => self.make_token(.right_paren),
            '{' => self.make_token(.left_brace),
            '}' => self.make_token(.right_brace),
            ';' => self.make_token(.semicolon),
            ',' => self.make_token(.comma),
            '.' => self.make_token(.dot),
            '-' => self.make_token(.minus),
            '+' => self.make_token(.plus),
            '/' => self.make_token(.slash),
            '*' => self.make_token(.star),
            '!' => if (self.match('=')) self.make_token(.bang_equal) else self.make_token(.bang),
            '=' => if (self.match('=')) self.make_token(.equal_equal) else self.make_token(.equal),
            '<' => if (self.match('=')) self.make_token(.less_equal) else self.make_token(.less),
            '>' => if (self.match('=')) self.make_token(.greater_equal) else self.make_token(.greater),
            '"' => self.string(),
            // '' => return self.make_token(.),
            else => self.make_error_token("Unexpected character."),
        };
    }

    fn identifier(self: *Self) Token {
        while (is_alpha(self.peek()) or ascii.isDigit(self.peek())) _ = self.advance();
        return self.make_token(self.identifier_kind());
    }

    fn identifier_kind(self: Self) Token_Kind {
        return switch (self.start[0]) {
            'a' => self.check_keyword(1, "nd", .and_),
            'c' => self.check_keyword(1, "lass", .class),
            'e' => self.check_keyword(1, "lse", .else_),
            'i' => self.check_keyword(1, "f", .if_),
            'n' => self.check_keyword(1, "il", .nil),
            'o' => self.check_keyword(1, "r", .or_),
            'p' => self.check_keyword(1, "rint", .print),
            'r' => self.check_keyword(1, "eturn", .return_),
            's' => self.check_keyword(1, "uper", .super),
            'v' => self.check_keyword(1, "ar", .var_),
            'w' => self.check_keyword(1, "hile", .while_),
            'f' => blk: {
                const token_len = self.token_length();
                if (1 < token_len) {
                    break :blk switch (self.start[1]) {
                        'a' => self.check_keyword(2, "lse", .false_),
                        'o' => self.check_keyword(2, "r", .for_),
                        'u' => self.check_keyword(2, "n", .fun),
                        else => .identifier,
                    };
                }
                break :blk .identifier;
            },
            else => .identifier,
            't' => blk: {
                const token_len = self.token_length();
                if (1 < token_len) {
                    break :blk switch (self.start[1]) {
                        'h' => self.check_keyword(2, "is", .this),
                        'r' => self.check_keyword(2, "ue", .true),
                        else => .identifier,
                    };
                }
                break :blk .identifier;
            },
        };
    }

    fn token_length(self: Self) usize {
        return @ptrToInt(self.current) - @ptrToInt(self.start);
    }

    fn check_keyword(self: Self, start: usize, rest: []const u8, kind: Token_Kind) Token_Kind {
        const token_len = self.token_length();
        const keyword_len = start + rest.len;

        if (token_len == keyword_len and mem.eql(u8, self.start[start..token_len], rest)) {
            return kind;
        }

        return .identifier;
    }

    fn number(self: *Self) Token {
        while (ascii.isDigit(self.peek())) _ = self.advance();

        if (self.peek() == '.' and ascii.isDigit(self.peek_next())) {
            _ = self.advance();
            while (ascii.isDigit(self.peek())) _ = self.advance();
        }

        return self.make_token(.number);
    }

    fn string(self: *Self) Token {
        while (self.peek() != '"' and !self.is_at_end()) {
            if (self.peek() == '\n') self.line += 1;
            _ = self.advance();
        }

        if (self.is_at_end()) return self.make_error_token("Unterminated string.");

        _ = self.advance();
        return self.make_token(.string);
    }

    fn match(self: *Self, expected: u8) bool {
        if (self.is_at_end()) return false;
        if (self.current[0] != expected) return false;
        self.current += 1;
        return true;
    }

    fn skip_whitespace(self: *Self) void {
        while (true) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t' => _ = self.advance(),
                '\n' => {
                    self.line += 1;
                    _ = self.advance();
                },
                '/' => if (self.peek_next() == '/') {
                    while (self.peek() != '\n' and !self.is_at_end()) {
                        _ = self.advance();
                    }
                } else {
                    return;
                },
                else => return,
            }
        }
    }

    fn peek(self: Self) u8 {
        return self.current[0];
    }

    fn peek_next(self: Self) u8 {
        if (self.is_at_end()) return 0;
        return self.current[1];
    }

    fn advance(self: *Self) u8 {
        const current = self.current[0];
        self.current += 1;
        return current;
    }

    fn make_token(self: Self, kind: Token_Kind) Token {
        const token_len = self.token_length();
        return .{
            .kind = kind,
            .lexeme = self.start[0..token_len],
            .line = self.line,
        };
    }

    fn make_error_token(self: Self, message: []const u8) Token {
        return .{
            .kind = .error_,
            .lexeme = message,
            .line = self.line,
        };
    }

    fn is_at_end(self: Self) bool {
        return self.end <= @ptrToInt(self.current);
    }
};

fn is_alpha(c: u8) bool {
    return ascii.isAlphabetic(c) or c == '_';
}
