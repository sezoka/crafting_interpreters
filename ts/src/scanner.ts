import { Token } from "./token.js";
import { TokenType } from "./token_type.js";
import { error } from "./main.js";


export class Scanner {
    src: string;
    tokens: Token[];
    start: number;
    current: number;
    line: number;
    keywords: Map<string, TokenType>;

    constructor(src: string) {
        this.src = src;
        this.tokens = [];
        this.start = 0;
        this.current = 0;
        this.line = 0;

        this.keywords = new Map();
        this.keywords.set("and", TokenType.AND);
        this.keywords.set("class", TokenType.CLASS);
        this.keywords.set("else", TokenType.ELSE);
        this.keywords.set("false", TokenType.FALSE);
        this.keywords.set("for", TokenType.FOR);
        this.keywords.set("fun", TokenType.FUN);
        this.keywords.set("if", TokenType.IF);
        this.keywords.set("nil", TokenType.NIL);
        this.keywords.set("or", TokenType.OR);
        this.keywords.set("print", TokenType.PRINT);
        this.keywords.set("return", TokenType.RETURN);
        this.keywords.set("super", TokenType.SUPER);
        this.keywords.set("this", TokenType.THIS);
        this.keywords.set("true", TokenType.TRUE);
        this.keywords.set("var", TokenType.VAR);
        this.keywords.set("while", TokenType.WHILE);
        this.keywords.set("continue", TokenType.CONTINUE);
        this.keywords.set("break", TokenType.BREAK);
        this.keywords.set("div", TokenType.DIV);
    }

    isAtEnd(): boolean {
        return this.src.length <= this.current;
    }

    advance(): string {
        const char = this.src[this.current];
        this.current += 1;
        return char;
    }

    addToken(type: TokenType, literal?: string | number): void {
        const lexeme = this.src.substring(this.start, this.current);
        let token = new Token(type, lexeme, literal ?? null, this.line);
        this.tokens.push(token);
    }

    match(char: string): boolean {
        if (this.isAtEnd()) return false;
        if (this.src[this.current] !== char) return false;
        this.current += 1;
        return true;
    }

    peek(): string {
        if (this.isAtEnd()) return "\0";
        return this.src[this.current];
    }

    peekNext(): string {
        if (this.src.length <= this.current + 1) return "\0";
        return this.src[this.current + 1];
    }

    string() {
        while (this.peek() != '"' && !this.isAtEnd()) {
            if (this.peek() === "\n") this.line += 1;
            this.advance();
        }

        if (this.isAtEnd()) {
            error(this.line, "Unterminated string");
            return;
        }

        this.advance();
        const str = this.src.substring(this.start + 1, this.current - 1);
        this.addToken(TokenType.STRING, str);
    }

    isDigit(c: string): boolean {
        return "0" <= c && c <= "9";
    }

    isAlpha(c: string): boolean {
        return ("a" <= c && c <= "z") ||
            ("A" <= c && c <= "Z") ||
            c === "_";
    }

    isAlphaNumeric(c: string): boolean {
        return this.isDigit(c) || this.isAlpha(c);
    }

    number() {
        while (this.isDigit(this.peek())) this.advance();

        if (this.peek() === "." && this.isDigit(this.peekNext())) {
            this.advance();
            while (this.isDigit(this.peek())) this.advance();
        }

        this.addToken(TokenType.NUMBER, parseFloat(this.src.substring(this.start, this.current)));
    }

    identifier() {
        while (this.isAlphaNumeric(this.peek())) this.advance();
        const text = this.src.substring(this.start, this.current);
        const type = this.keywords.get(text) ?? TokenType.IDENTIFIER;
        this.addToken(type);
    }

    scanToken(): Token | null {
        const c = this.advance();
        switch (c) {
            case "?": this.addToken(TokenType.QUESTION); break;
            case ":": this.addToken(TokenType.COLON); break;
            case "(": this.addToken(TokenType.LEFT_PAREN); break;
            case ")": this.addToken(TokenType.RIGHT_PAREN); break;
            case "{": this.addToken(TokenType.LEFT_BRACE); break;
            case "}": this.addToken(TokenType.RIGHT_BRACE); break;
            case ",": this.addToken(TokenType.COMMA); break;
            case ".": this.addToken(TokenType.DOT); break;
            case "-": this.addToken(TokenType.MINUS); break;
            case "+": this.addToken(TokenType.PLUS); break;
            case ";": this.addToken(TokenType.SEMICOLON); break;
            case "*": this.addToken(TokenType.STAR); break;
            case "!": this.addToken(this.match("=") ? TokenType.BANG_EQUAL : TokenType.BANG); break;
            case "=": this.addToken(this.match("=") ? TokenType.EQUAL_EQUAL : TokenType.EQUAL); break;
            case "<": this.addToken(this.match("=") ? TokenType.LESS_EQUAL : TokenType.LESS); break;
            case ">": this.addToken(this.match("=") ? TokenType.GREATER_EQUAL : TokenType.GREATER); break;
            case "%": this.addToken(TokenType.PERCENT); break;
            case "/":
                if (this.match("/")) {
                    while (this.peek() !== "\n" && !this.isAtEnd()) this.advance();
                } else if (this.match("*")) {
                    let nesting = 1;
                    while (nesting !== 0 && !this.isAtEnd()) {
                        if (this.match("/") && this.match("*")) nesting += 1;
                        if (this.match("*") && this.match("/")) nesting -= 1;
                        this.advance();
                    }
                } else {
                    this.addToken(TokenType.SLASH);
                }
                break;
            case " ":
            case "\r":
            case "\t":
                break;
            case "\n":
                this.line += 1;
                break;
            case '"': this.string(); break;
            default:
                if (this.isDigit(c)) {
                    this.number();
                } else if (this.isAlpha(c)) {
                    this.identifier();
                } else {
                    error(this.line, `unexpected character '${c}'`);
                }
        }

        return null;
    }

    scanTokens(): Token[] {
        while (!this.isAtEnd()) {
            this.start = this.current;
            this.scanToken();
        }

        const token = new Token(TokenType.EOF, "\0", null, this.line);
        this.tokens.push(token);

        return this.tokens;
    }
}
