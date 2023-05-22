import { Assign, Binary, Call, Comma, Expr, Grouping, Logical, Ternary, Unary, Value, Variable, Visitor as ExprVisitor } from "./Expr.js";
import { Block, Expression, Func, If, Print, Return, Stmt, Var, Visitor as StmtVisitor, While } from "./Stmt.js";
import { Interpreter } from "./interpreter.js";
import { Token } from "./token.js";
import { error } from "./main.js";


enum FunctionType {
    NONE,
    FUNCTION,
}


export class Resolver implements ExprVisitor<Value>, StmtVisitor<void> {
    interpreter: Interpreter;
    scopes: Map<string, boolean>[] = [];
    current_function = FunctionType.NONE;

    constructor(interpreter: Interpreter) {
        this.interpreter = interpreter;
    }

    visitBlockStmt(stmt: Block): void {
        this.beginScope();
        this.resolveStmt(stmt.statements);
        this.endScope();
    }

    visitVarStmt(stmt: Var): void {
        this.declare(stmt.name);
        this.resolveExpr(stmt.initializer);
        this.define(stmt.name);
    }

    resolveStmt(statements: Stmt[] | Stmt): void {
        if (Array.isArray(statements)) {
            for (const statement of statements) {
                this.resolveStmt(statement);
            }
        } else {
            statements.accept(this);
        }
    }

    resolveExpr(expr: Expr): void {
        expr.accept(this);
    }

    resolveFunction(func: Func, type: FunctionType) {
        const enclosing_function = this.current_function;
        this.current_function = type;

        this.beginScope();
        for (const param of func.params) {
            this.declare(param);
            this.define(param);
        }
        this.resolveStmt(func.body);
        this.endScope();

        this.current_function = enclosing_function;
    }

    beginScope(): void {
        this.scopes.push(new Map());
    }

    endScope(): void {
        this.scopes.pop();
    }

    declare(name: Token): void {
        if (this.scopes.length === 0) return;
        const scope = this.scopes[this.scopes.length - 1];
        if (scope.has(name.lexeme)) {
            error(name, "Already a variable with this name in this scope.");
        }
        scope.set(name.lexeme, false);
    }

    define(name: Token): void {
        if (this.scopes.length === 0) return;
        this.scopes[this.scopes.length - 1].set(name.lexeme, true);
    }

    resolveLocal(expr: Expr, name: Token) {
        for (let i = this.scopes.length - 1; 0 <= i; i -= 1) {
            if (this.scopes[i].has(name.lexeme)) {
                this.interpreter.resolve(expr, this.scopes.length - 1 - i);
                return;
            }
        }
    }

    visitExpressionStmt(stmt: Expression): void {
        this.resolveExpr(stmt.expression);
    }

    visitFuncStmt(stmt: Func): void {
        this.declare(stmt.name);
        this.define(stmt.name);

        this.resolveFunction(stmt, FunctionType.FUNCTION);
    }

    visitIfStmt(stmt: If): void {
        this.resolveExpr(stmt.condition);
        this.resolveStmt(stmt.then_branch);
        if (stmt.else_branch !== null) this.resolveStmt(stmt.else_branch);
    }

    visitPrintStmt(stmt: Print): void {
        this.resolveExpr(stmt.expression);
    }

    visitReturnStmt(stmt: Return): void {
        if (this.current_function === FunctionType.NONE) {
            error(stmt.keyword, "Can't return from top-level code.");
        }

        if (stmt.value !== null) {
            this.resolveExpr(stmt.value);
        }
    }

    visitWhileStmt(stmt: While): void {
        this.resolveExpr(stmt.condition);
        this.resolveStmt(stmt.body);
    }

    visitBreakStmt(): void { }

    visitContinueStmt(): void { }

    visitAssignExpr(expr: Assign): null {
        this.resolveExpr(expr.value);
        this.resolveLocal(expr, expr.name);
        return null;
    }

    visitBinaryExpr(expr: Binary): null {
        this.resolveExpr(expr.left);
        this.resolveExpr(expr.right);
        return null;
    }

    visitCallExpr(expr: Call): null {
        this.resolveExpr(expr.callee);

        for (const arg of expr.args) {
            this.resolveExpr(arg);
        }

        return null;
    }

    visitGroupingExpr(expr: Grouping): null {
        this.resolveExpr(expr.expression);
        return null;
    }

    visitLiteralExpr(): null {
        return null;
    }

    visitLogicalExpr(expr: Logical): null {
        this.resolveExpr(expr.left);
        this.resolveExpr(expr.right);
        return null;
    }

    visitUnaryExpr(expr: Unary): null {
        this.resolveExpr(expr.right)
        return null;
    }

    visitVariableExpr(expr: Variable): null {
        if (this.scopes.length !== 0 && this.scopes[this.scopes.length - 1].get(expr.name.lexeme) === false) {
            error(expr.name, "Can't read local variable in its own initializer.");
        }

        this.resolveLocal(expr, expr.name);
        return null;
    }

    visitCommaExpr(expr: Comma): null {
        this.resolveExpr(expr.left);
        this.resolveExpr(expr.right);
        return null;
    }

    visitTernaryExpr(expr: Ternary): null {
        this.resolveExpr(expr.cond);
        this.resolveExpr(expr.truthy);
        this.resolveExpr(expr.falsey);
        return null;
    }

}
