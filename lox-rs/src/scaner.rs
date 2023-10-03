pub struct Token<'a> {
    pub kind: TokenKind,
    pub lexeme: &'a str,
    pub line: u16,
}

#[derive(PartialEq, Eq, Debug)]
pub enum TokenKind {
    // Single-character tokens.
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    Comma,
    Dot,
    Minus,
    Plus,
    Semicolon,
    Slash,
    Star,
    // One or two character tokens.
    Bang,
    BangEqual,
    Equal,
    EqualEqual,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,
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
}

pub struct Scanner<'a> {
    src: &'a str,
    start: usize,
    current: usize,
    line: u16,
}

impl<'a> Scanner<'a> {
    pub fn new(src: &str) -> Scanner {
        Scanner {
            src,
            start: 0,
            current: 0,
            line: 1,
        }
    }

    pub fn scan_token(&mut self) -> Token<'a> {
        self.skip_whitespace();

        self.start = self.current;
        if self.is_at_end() {
            return self.make_token(TokenKind::Eof);
        }

        let c = self.advance();
        return match c {
            '(' => self.make_token(TokenKind::LeftParen),
            ')' => self.make_token(TokenKind::RightParen),
            '{' => self.make_token(TokenKind::LeftBrace),
            '}' => self.make_token(TokenKind::RightBrace),
            ';' => self.make_token(TokenKind::Semicolon),
            ',' => self.make_token(TokenKind::Comma),
            '.' => self.make_token(TokenKind::Dot),
            '-' => self.make_token(TokenKind::Minus),
            '+' => self.make_token(TokenKind::Plus),
            '/' => self.make_token(TokenKind::Slash),
            '*' => self.make_token(TokenKind::Star),
            '!' => {
                if self.matches('=') {
                    self.make_token(TokenKind::BangEqual)
                } else {
                    self.make_token(TokenKind::Bang)
                }
            }
            '=' => {
                if self.matches('=') {
                    self.make_token(TokenKind::EqualEqual)
                } else {
                    self.make_token(TokenKind::Equal)
                }
            }
            '<' => {
                if self.matches('=') {
                    self.make_token(TokenKind::LessEqual)
                } else {
                    self.make_token(TokenKind::Less)
                }
            }
            '>' => {
                if self.matches('=') {
                    self.make_token(TokenKind::GreaterEqual)
                } else {
                    self.make_token(TokenKind::Greater)
                }
            }
            '"' => self.string(),
            _ => {
                if c.is_ascii_digit() {
                    return self.number();
                }
                if is_alpha(c) {
                    return self.identifier();
                }
                return self.error_token("Unexpected character.");
            }
        };
    }

    fn identifier(&mut self) -> Token<'a> {
        while is_alpha(self.peek()) || self.peek().is_ascii_digit() {
            self.advance();
        }

        let kind = self.identifier_kind();
        return self.make_token(kind);
    }

    fn identifier_kind(&self) -> TokenKind {
        match self.src.as_bytes()[self.start] as char {
            'a' => self.check_keyword(1, "nd", TokenKind::And),
            'c' => self.check_keyword(1, "lass", TokenKind::Class),
            'e' => self.check_keyword(1, "lse", TokenKind::Else),
            'f' if 1 < self.current - self.start => {
                match self.src.as_bytes()[self.start + 1] as char {
                    'a' => self.check_keyword(2, "lse", TokenKind::False),
                    'o' => self.check_keyword(2, "r", TokenKind::For),
                    'u' => self.check_keyword(2, "n", TokenKind::Fun),
                    _ => TokenKind::Identifier,
                }
            }
            'i' => self.check_keyword(1, "f", TokenKind::If),
            'n' => self.check_keyword(1, "il", TokenKind::Nil),
            'o' => self.check_keyword(1, "r", TokenKind::Or),
            'p' => self.check_keyword(1, "rint", TokenKind::Print),
            'r' => self.check_keyword(1, "eturn", TokenKind::Return),
            's' => self.check_keyword(1, "uper", TokenKind::Super),
            't' if 1 < self.current - self.start => {
                match self.src.as_bytes()[self.start + 1] as char {
                    'h' => self.check_keyword(2, "is", TokenKind::This),
                    'r' => self.check_keyword(2, "ue", TokenKind::True),
                    _ => TokenKind::Identifier,
                }
            }
            'v' => self.check_keyword(1, "ar", TokenKind::Var),
            'w' => self.check_keyword(1, "hile", TokenKind::While),
            _ => TokenKind::Identifier,
        }
    }

    fn check_keyword(&self, start: usize, rest: &str, kind: TokenKind) -> TokenKind {
        let len = self.current - self.start;
        if len != rest.len() + start {
            return TokenKind::Identifier;
        }
        if &self.src[start..start + rest.len()] == rest {
            return kind;
        }
        return TokenKind::Identifier;
    }

    fn number(&mut self) -> Token<'a> {
        while self.peek().is_ascii_digit() {
            self.advance();
        }
        if self.peek() == '.' && self.peek_next().is_ascii_digit() {
            self.advance();
            while self.peek().is_ascii_digit() {
                self.advance();
            }
        }
        return self.make_token(TokenKind::Number);
    }

    fn string(&mut self) -> Token<'a> {
        while self.peek() != '"' && !self.is_at_end() {
            if self.peek() == '\n' {
                self.line += 1;
            }
            self.advance();
        }
        if self.is_at_end() {
            return self.error_token("Unterminated string.");
        }
        self.advance();
        return self.make_token(TokenKind::String);
    }

    fn skip_whitespace(&mut self) {
        loop {
            let c = self.peek();
            match c {
                ' ' | '\r' | '\t' => {
                    self.advance();
                }
                '\n' => {
                    self.line += 1;
                    self.advance();
                }
                '/' => {
                    if self.peek_next() == '/' {
                        while !self.is_at_end() && self.peek() != '\n' {
                            self.advance();
                        }
                    } else {
                        return;
                    };
                }
                _ => {
                    return;
                }
            };
        }
    }

    fn peek_next(&self) -> char {
        if self.is_at_end() {
            return '\0';
        }
        return self.src.as_bytes()[self.current + 1] as char;
    }

    fn matches(&mut self, ch: char) -> bool {
        if self.is_at_end() {
            return false;
        }
        if self.src.as_bytes()[self.current] as char != ch {
            return false;
        }
        self.current += 1;
        return true;
    }

    fn peek(&mut self) -> char {
        if self.is_at_end() {
            return '\0';
        }
        self.src.as_bytes()[self.current] as char
    }

    fn advance(&mut self) -> char {
        let curr = self.src.as_bytes()[self.current] as char;
        self.current += 1;
        return curr;
    }

    fn make_token(&mut self, kind: TokenKind) -> Token<'a> {
        return Token {
            line: self.line,
            lexeme: &self.src[self.start..self.current],
            kind,
        };
    }

    fn error_token(&mut self, msg: &'a str) -> Token<'a> {
        return Token {
            line: self.line,
            lexeme: msg,
            kind: TokenKind::Error,
        };
    }

    fn is_at_end(&self) -> bool {
        return self.src.len() <= self.current;
    }
}

fn is_alpha(ch: char) -> bool {
    ch.is_ascii_alphabetic() || ch == '_'
}
