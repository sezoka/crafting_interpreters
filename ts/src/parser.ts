import { Token } from "./token";
import { Assign, Binary, Call, Comma, Expr, Get, Grouping, Literal, Logical, Ternary, Unary, Variable, Set as SetExp, This, Super } from "./Expr.js";
import { TokenType } from "./token_type.js";
import { error } from "./main.js";
import { Print, Stmt, Expression, Var, Block, If, While, Break, Continue, Func, Return, Class } from "./Stmt.js";

class ParseError extends Error { }

export class Parser {
    tokens: Token[];
    current: number;
    loop_nesting_level = 0;

    constructor(tokens: Token[]) {
        this.tokens = tokens;
        this.current = 0;
    }

    parse(): Stmt[] {
        const statements = [];

        while (!this.isAtEnd()) {
            const stmt = this.declaration();
            if (stmt !== null) {
                statements.push(stmt);
            }
        }

        return statements;
    }

    comma(): Expr {
        let expr = this.equality();

        while (this.match([TokenType.COMMA])) {
            const right = this.equality();
            expr = new Comma(expr, right);
        }

        return expr;
    }

    ternary(): Expr {
        let expr = this.comma();

        if (this.match([TokenType.QUESTION])) {
            const truthy = this.comma();
            this.consume(TokenType.COLON, "Expected ':'")
            const falsey = this.comma();
            return new Ternary(expr, truthy, falsey);
        }

        return expr;
    }

    expression(): Expr {
        return this.assignment();
    }

    declaration(): Stmt | null {
        try {
            if (this.match([TokenType.CLASS])) return this.classDeclaration();
            if (this.match([TokenType.FUN])) return this.func("function");
            if (this.match([TokenType.VAR])) return this.varDeclaration();
            return this.statement();
        } catch (error: any) {
            this.synchronize();
            return null;
        }
    }

    classDeclaration(): Stmt {
        const name = this.consume(TokenType.IDENTIFIER, "Expect class name.");

        let superclass = null;
        if (this.match([TokenType.LESS])) {
            this.consume(TokenType.IDENTIFIER, "Expect superclass name.");
            superclass = new Variable(this.previous());
        }

        this.consume(TokenType.LEFT_BRACE, "Expect '{' before class body.");

        const methods: Func[] = [];
        while (!this.check(TokenType.RIGHT_BRACE) && !this.isAtEnd()) {
            methods.push(this.func("method"));
        }

        this.consume(TokenType.RIGHT_BRACE, "Expect '}' after class body.");

        return new Class(name, superclass, methods);
    }

    func(kind: string): Func {
        const name = this.consume(TokenType.IDENTIFIER, "Expect " + kind + " name.");
        this.consume(TokenType.LEFT_PAREN, "Expect '(' after " + kind + " name.");
        const params: Token[] = [];
        if (!this.check(TokenType.RIGHT_PAREN)) {
            do {
                if (255 <= params.length) {
                    this.error(this.peek(), "Can't have more than 255 parameters.");
                }

                params.push(this.consume(TokenType.IDENTIFIER, "Expect paramenter name."));
            } while (this.match([TokenType.COMMA]))
        }
        this.consume(TokenType.RIGHT_PAREN, "Expect ')', after parameters.");

        this.consume(TokenType.LEFT_BRACE, "Expect '{', before " + kind + " body.");
        const body = this.block();
        return new Func(name, params, body);
    }

    statement(): Stmt {
        if (this.match([TokenType.FOR])) return this.forStatement();
        if (this.match([TokenType.IF])) return this.ifStatement();
        if (this.match([TokenType.PRINT])) return this.printStatement();
        if (this.match([TokenType.RETURN])) return this.returnStatement();
        if (this.match([TokenType.WHILE])) return this.whileStatement();
        if (this.match([TokenType.LEFT_BRACE])) return new Block(this.block());

        if (this.match([TokenType.BREAK])) {
            if (0 < this.loop_nesting_level) {
                this.consume(TokenType.SEMICOLON, "Expect ';' after 'break'.");
                return new Break();
            }
            throw this.error(this.previous(), "'break' statement should be in for or while loop body");
        };
        if (this.match([TokenType.CONTINUE])) {
            if (0 < this.loop_nesting_level) {
                this.consume(TokenType.SEMICOLON, "Expect ';' after 'continue'.");
                return new Continue();
            }
            throw this.error(this.previous(), "'continue' statement should be in 'for' or 'while' loop body");
        };

        return this.expressionStatement();
    }

    forStatement(): Stmt {
        this.consume(TokenType.LEFT_PAREN, "Expect '(' after 'for'.");

        let initializer;
        if (this.match([TokenType.SEMICOLON])) {
            initializer = null;
        } else if (this.match([TokenType.VAR])) {
            initializer = this.varDeclaration();
        } else {
            initializer = this.expressionStatement();
        }

        let condition = null;
        if (!this.check(TokenType.SEMICOLON)) {
            condition = this.expression();
        }
        this.consume(TokenType.SEMICOLON, "Expect ';' after loop condition.");

        let increment = null;
        if (!this.check(TokenType.RIGHT_PAREN)) {
            increment = this.expression();
        }
        this.consume(TokenType.RIGHT_PAREN, "Expect ')' after for clauses.");

        let body: Stmt = this.statement();

        if (increment !== null) {
            body = new Block([body, new Expression(increment)]);
        }

        if (condition === null) {
            condition = new Literal(true);
        }

        body = new While(condition, body);

        if (initializer !== null) {
            body = new Block([initializer, body]);
        }

        return body;
    }

    ifStatement(): Stmt {
        this.loop_nesting_level += 1;

        this.consume(TokenType.LEFT_PAREN, "Expect '(' after 'if'.");
        const condition = this.expression();
        this.consume(TokenType.RIGHT_PAREN, "Expect ')' after if condition.");

        const then_branch = this.statement();
        let else_branch = null;
        if (this.match([TokenType.ELSE])) {
            else_branch = this.statement();
        }

        this.loop_nesting_level -= 1;

        return new If(condition, then_branch, else_branch);
    }

    printStatement(): Stmt {
        const value = this.expression();
        this.consume(TokenType.SEMICOLON, "Expect ';' after value");
        return new Print(value);
    }

    returnStatement(): Stmt {
        const keyword = this.previous();
        let value = null;
        if (!this.check(TokenType.SEMICOLON)) {
            value = this.expression();
        }

        this.consume(TokenType.SEMICOLON, "Expect ';' after return value.");
        return new Return(keyword, value);
    }

    varDeclaration(): Stmt {
        const name = this.consume(TokenType.IDENTIFIER, "Expect variable name.");

        let initializer: Expr | null = null;
        if (this.match([TokenType.EQUAL])) {
            initializer = this.expression();
        }

        if (initializer === null) {
            throw this.error(this.peek(), "No initializer for variable '" + name.lexeme + "'");
        }

        this.consume(TokenType.SEMICOLON, "Expect ';' after variable declaration.");
        return new Var(name, initializer);
    }

    whileStatement(): Stmt {
        this.loop_nesting_level += 1;

        this.consume(TokenType.LEFT_PAREN, "Expect '(' after 'while'.");
        const condition = this.expression();
        this.consume(TokenType.RIGHT_PAREN, "Expect ')' after condition.");
        const body = this.statement();

        this.loop_nesting_level -= 1;

        return new While(condition, body);
    }

    expressionStatement(): Stmt {
        const expr = this.expression();
        this.consume(TokenType.SEMICOLON, "Expect ';' after expression.");
        return new Expression(expr);
    }

    block(): Stmt[] {
        const statements: Stmt[] = [];

        while (!this.check(TokenType.RIGHT_BRACE) && !this.isAtEnd()) {
            const stmt = this.declaration();
            if (stmt !== null) {
                statements.push(stmt);
            }
        }

        this.consume(TokenType.RIGHT_BRACE, "Expect '}' after block");
        return statements;
    }

    assignment(): Expr {
        let expr = this.or();

        if (this.match([TokenType.EQUAL])) {
            const equals = this.previous();
            const value = this.assignment();

            if (expr instanceof Variable) {
                return new Assign(expr.name, value);
            } else if (expr instanceof Get) {
                const get = expr;
                return new SetExp(get.object, get.name, value);
            }

            this.error(equals, "Invalid assignment target.");
        }

        return expr;
    }

    or(): Expr {
        let expr = this.and();

        while (this.match([TokenType.OR])) {
            const operator = this.previous();
            const right = this.and();
            expr = new Logical(expr, operator, right);
        }

        return expr;
    }

    and(): Expr {
        let expr = this.equality();

        while (this.match([TokenType.AND])) {
            const operator = this.previous();
            const right = this.equality();
            expr = new Logical(expr, operator, right);
        }

        return expr;
    }

    peek(): Token {
        return this.tokens[this.current];
    }

    isAtEnd(): boolean {
        return this.peek().type === TokenType.EOF;
    }

    check(type: TokenType): boolean {
        if (this.isAtEnd()) return false;
        return this.peek().type === type;
    }

    previous(): Token {
        return this.tokens[this.current - 1];
    }

    advance(): Token {
        if (!this.isAtEnd()) this.current += 1;
        return this.previous();
    }

    match(types: TokenType[]): boolean {
        for (const type of types) {
            if (this.check(type)) {
                this.advance();
                return true;
            }
        }

        return false;
    }

    synchronize() {
        this.advance();

        while (!this.isAtEnd()) {
            if (this.previous().type === TokenType.SEMICOLON) return;

            switch (this.peek().type) {
                case TokenType.CLASS:
                case TokenType.FUN:
                case TokenType.VAR:
                case TokenType.FOR:
                case TokenType.IF:
                case TokenType.WHILE:
                case TokenType.PRINT:
                case TokenType.RETURN:
                    return;
            }

            this.advance();
        }
    }

    error(token: Token, message: string): ParseError {
        error(token, message);
        return new ParseError();
    }

    consume(type: TokenType, message: string): Token {
        if (this.check(type)) return this.advance();
        throw this.error(this.peek(), message);
    }

    primary(): Expr {
        if (this.match([TokenType.FALSE])) return new Literal(false);
        if (this.match([TokenType.TRUE])) return new Literal(true);
        if (this.match([TokenType.NIL])) return new Literal(null);

        if (this.match([TokenType.NUMBER, TokenType.STRING])) {
            return new Literal(this.previous().literal);
        }

        if (this.match([TokenType.SUPER])) {
            const keyword = this.previous();
            this.consume(TokenType.DOT, "Expect '.' after 'super'.");
            const method = this.consume(TokenType.IDENTIFIER, "Expect superclass method name.");
            return new Super(keyword, method);
        }

        if (this.match([TokenType.THIS])) return new This(this.previous());

        if (this.match([TokenType.IDENTIFIER])) {
            return new Variable(this.previous());
        }

        if (this.match([TokenType.LEFT_PAREN])) {
            const expr = this.expression();
            this.consume(TokenType.RIGHT_PAREN, "Expect ')' after expression.");
            return new Grouping(expr);
        }

        throw this.error(this.peek(), "Expect expression.");
    }

    unary(): Expr {
        if (this.match([TokenType.BANG, TokenType.MINUS])) {
            const op = this.previous();
            const right = this.unary();
            return new Unary(op, right);
        }

        return this.call();
    }

    finishCall(callee: Expr): Expr {
        const args = [];
        if (!this.check(TokenType.RIGHT_PAREN)) {
            do {
                if (255 <= args.length) {
                    this.error(this.peek(), "Can't have more than 255 arguments");
                }
                args.push(this.expression());
            } while (this.match([TokenType.COMMA]));
        }

        const paren = this.consume(TokenType.RIGHT_PAREN, "Expect ')' after arguments.");

        return new Call(callee, paren, args);
    }

    call(): Expr {
        let expr = this.primary();

        while (true) {
            if (this.match([TokenType.LEFT_PAREN])) {
                expr = this.finishCall(expr);
            } else if (this.match([TokenType.DOT])) {
                const name = this.consume(TokenType.IDENTIFIER, "Expect property name after '.'.");
                expr = new Get(expr, name);
            } else {
                break;
            }
        }

        return expr;
    }

    factor(): Expr {
        let expr = this.unary();

        while (this.match([TokenType.SLASH, TokenType.STAR, TokenType.PERCENT, TokenType.DIV])) {
            const op = this.previous();
            const right = this.unary();
            expr = new Binary(expr, op, right);
        }

        return expr;
    }

    term(): Expr {
        let expr = this.factor();

        while (this.match([TokenType.MINUS, TokenType.PLUS])) {
            const op = this.previous();
            const right = this.factor();
            expr = new Binary(expr, op, right);
        }

        return expr;
    }

    comparison(): Expr {
        let expr = this.term();

        while (this.match([TokenType.GREATER, TokenType.GREATER_EQUAL,
        TokenType.LESS, TokenType.LESS_EQUAL])) {
            const op = this.previous();
            const right = this.term();
            expr = new Binary(expr, op, right);
        }

        return expr;
    }

    equality(): Expr {
        let expr = this.comparison();

        while (this.match([TokenType.BANG_EQUAL, TokenType.EQUAL_EQUAL])) {
            const op = this.previous();
            const right = this.comparison();
            expr = new Binary(expr, op, right);
        }

        return expr;
    }

}

