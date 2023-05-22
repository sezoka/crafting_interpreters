import { Token } from "./token.js";

export type Value = string | number | boolean | Object | null;

export interface Expr {
    accept<T>(visitor: Visitor<T>): T,
}

export interface Visitor<T> {
    visitAssignExpr: (expr: Assign) => T,
    visitBinaryExpr: (expr: Binary) => T,
    visitCallExpr: (expr: Call) => T,
    visitGetExpr: (expr: Get) => T,
    visitGroupingExpr: (expr: Grouping) => T,
    visitLiteralExpr: (expr: Literal) => T,
    visitLogicalExpr: (expr: Logical) => T,
    visitSetExpr: (expr: Set) => T,
    visitSuperExpr: (expr: Super) => T,
    visitThisExpr: (expr: This) => T,
    visitUnaryExpr: (expr: Unary) => T,
    visitVariableExpr: (expr: Variable) => T,
    visitCommaExpr: (expr: Comma) => T,
    visitTernaryExpr: (expr: Ternary) => T,
}

export class Assign implements Expr {
    name: Token;
    value: Expr;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitAssignExpr(this);
    }

    constructor(name: Token, value: Expr) {
        this.name = name;
        this.value = value;
    }
}

export class Binary implements Expr {
    left: Expr;
    operator: Token;
    right: Expr;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitBinaryExpr(this);
    }

    constructor(left: Expr, operator: Token, right: Expr) {
        this.left = left;
        this.operator = operator;
        this.right = right;
    }
}

export class Call implements Expr {
    callee: Expr;
    paren: Token;
    args: Expr[];

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitCallExpr(this);
    }

    constructor(callee: Expr, paren: Token, args: Expr[]) {
        this.callee = callee;
        this.paren = paren;
        this.args = args;
    }
}

export class Get implements Expr {
    object: Expr;
    name: Token;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitGetExpr(this);
    }

    constructor(object: Expr, name: Token) {
        this.object = object;
        this.name = name;
    }
}

export class Grouping implements Expr {
    expression: Expr;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitGroupingExpr(this);
    }

    constructor(expression: Expr) {
        this.expression = expression;
    }
}

export class Literal implements Expr {
    value: Value;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitLiteralExpr(this);
    }

    constructor(value: Value) {
        this.value = value;
    }
}

export class Logical implements Expr {
    left: Expr;
    operator: Token;
    right: Expr;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitLogicalExpr(this);
    }

    constructor(left: Expr, operator: Token, right: Expr) {
        this.left = left;
        this.operator = operator;
        this.right = right;
    }
}

export class Set implements Expr {
    object: Expr;
    name: Token;
    value: Expr;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitSetExpr(this);
    }

    constructor(object: Expr, name: Token, value: Expr) {
        this.object = object;
        this.name = name;
        this.value = value;
    }
}

export class Super implements Expr {
    keyword: Token;
    method: Token;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitSuperExpr(this);
    }

    constructor(keyword: Token, method: Token) {
        this.keyword = keyword;
        this.method = method;
    }
}

export class This implements Expr {
    keyword: Token;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitThisExpr(this);
    }

    constructor(keyword: Token) {
        this.keyword = keyword;
    }
}

export class Unary implements Expr {
    operator: Token;
    right: Expr;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitUnaryExpr(this);
    }

    constructor(operator: Token, right: Expr) {
        this.operator = operator;
        this.right = right;
    }
}

export class Variable implements Expr {
    name: Token;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitVariableExpr(this);
    }

    constructor(name: Token) {
        this.name = name;
    }
}

export class Comma implements Expr {
    left: Expr;
    right: Expr;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitCommaExpr(this);
    }

    constructor(left: Expr, right: Expr) {
        this.left = left;
        this.right = right;
    }
}

export class Ternary implements Expr {
    cond: Expr;
    truthy: Expr;
    falsey: Expr;

    accept<T>(visitor: Visitor<T>): T {
        return visitor.visitTernaryExpr(this);
    }

    constructor(cond: Expr, truthy: Expr, falsey: Expr) {
        this.cond = cond;
        this.truthy = truthy;
        this.falsey = falsey;
    }
}
