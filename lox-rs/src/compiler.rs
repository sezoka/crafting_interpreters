use crate::scaner::{Scanner, TokenKind};

pub fn compile(src: &str) {
    let mut scanner = Scanner::new(src);
    let mut line = u16::MAX;
    loop {
        let token = scanner.scan_token();
        if token.line != line {
            print!("{:4} ", token.line);
            line = token.line;
        } else {
            print!("   | ");
        }
        println!("{} '{}'", format!("{:?}", token.kind).to_lowercase(), token.lexeme);
        if token.kind == TokenKind::Eof {
            break;
        }
    }
}
