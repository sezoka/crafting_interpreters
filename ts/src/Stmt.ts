import { Expr } from "./Expr.js";
import { Token } from "./token.js";

export type Value = string | number | boolean | Object | null;

export interface Stmt {
    accept<T>(visitor: Visitor<T>): T,
}

export interface Visitor<T> {
    visitBlockStmt: (stmt: Block) => T,
    visitExpressionStmt: (stmt: Expression) => T,
    visitFuncStmt: (stmt: Func) => T,
    visitIfStmt: (stmt: If) => T,
    visitPrintStmt: (stmt: Print) => T,
    visitReturnStmt: (stmt: Return) => T,
    visitVarStmt: (stmt: Var) => T,
    visitWhileStmt: (stmt: While) => T,
    visitBreakStmt: (stmt: Break) => T,
    visitContinueStmt: (stmt: Continue) => T,
}

export class Block implements Stmt {
    statements: Stmt[];

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitBlockStmt(this);
    }

    constructor(statements: Stmt[]) {
        this.statements = statements;
    }
}

export class Expression implements Stmt {
    expression: Expr;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitExpressionStmt(this);
    }

    constructor(expression: Expr) {
        this.expression = expression;
    }
}

export class Func implements Stmt {
    name: Token;
    params: Token[];
    body: Stmt[];

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitFuncStmt(this);
    }

    constructor(name: Token, params: Token[], body: Stmt[]) {
        this.name = name;
        this.params = params;
        this.body = body;
    }
}

export class If implements Stmt {
    condition: Expr;
    then_branch: Stmt;
    else_branch: Stmt | null;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitIfStmt(this);
    }

    constructor(condition: Expr, then_branch: Stmt, else_branch: Stmt | null) {
        this.condition = condition;
        this.then_branch = then_branch;
        this.else_branch = else_branch;
    }
}

export class Print implements Stmt {
    expression: Expr;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitPrintStmt(this);
    }

    constructor(expression: Expr) {
        this.expression = expression;
    }
}

export class Return implements Stmt {
    keyword: Token;
    value: Expr | null;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitReturnStmt(this);
    }

    constructor(keyword: Token, value: Expr | null) {
        this.keyword = keyword;
        this.value = value;
    }
}

export class Var implements Stmt {
    name: Token;
    initializer: Expr;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitVarStmt(this);
    }

    constructor(name: Token, initializer: Expr) {
        this.name = name;
        this.initializer = initializer;
    }
}

export class While implements Stmt {
    condition: Expr;
    body: Stmt;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitWhileStmt(this);
    }

    constructor(condition: Expr, body: Stmt) {
        this.condition = condition;
        this.body = body;
    }
}

export class Break implements Stmt {

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitBreakStmt(this);
    }

    constructor() {
    }
}

export class Continue implements Stmt {

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitContinueStmt(this);
    }

    constructor() {
    }
}
