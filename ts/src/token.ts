import { TokenType } from "./token_type.js";

export class Token {
    type: TokenType;
    lexeme: string;
    literal: Object | null;
    line: number;

    constructor(type: TokenType, lexeme: string, literal: Object | null, line: number) {
        this.type = type;
        this.lexeme = lexeme;
        this.literal = literal;
        this.line = line;
    }

    toString(): string {
        return `${this.type} ${this.lexeme} ${this.literal}`;
    }
}
