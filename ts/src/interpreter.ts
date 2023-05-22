import { Visitor as ExprVisitor, Expr, Literal, Value, Grouping, Unary, Binary, Comma, Ternary, Variable, Assign, Logical, Call, Get, Set as SetExpr, This, Super } from "./Expr.js";
import { Block, Class, Expression, Func, If, Print, Return, Stmt, Var, Visitor as StmtVisitor, While } from "./Stmt.js";
import { Token } from "./token.js";
import { TokenType } from "./token_type.js";
import { RuntimeError } from "./runtime_error.js";
import { runtimeError } from "./main.js";
import { Environment } from "./environment.js";
import { isCallable, LoxCallable } from "./lox_callable.js";
import { LoxFunction } from "./lox_function.js";
import { ReturnException } from "./return.js";
import { printSync, readLine } from "./utils.js";
import { LoxInstance } from "./lox_instance.js";
import { LoxClass } from "./lox_class.js";

class BreakException { }
class ContinueException { }

function isTruthy(val: Value): boolean {
    if (val === null) return false;
    if (typeof val === "boolean") return val;
    return true;
}

function isEqual(a: Value, b: Value) {
    if (a == null && b == null) return true;
    if (a == null) return false;

    return a === b;
}

export function stringify(object: Value) {
    if (object === null) return "nil";

    if (typeof object === "number") {
        let text = object.toString();
        if (text.endsWith(".0")) {
            text = text.substring(0, text.length - 2);
        }
        return text;
    }

    return object.toString();
}

export class Interpreter implements ExprVisitor<Value>, StmtVisitor<void> {
    globals: Environment = new Environment;
    environment = this.globals;
    locals = new Map<Expr, number>();

    constructor() {
        const clock: LoxCallable = {
            arity(): number { return 0; },
            call(): Value { return Math.trunc(performance.now() * 1000); },
            toString(): string { return "<native fn>"; }
        }
        this.globals.define("clock", clock);

        const read_line: LoxCallable = {
            arity(): number { return 0; },
            call(): Value { return readLine(); },
            toString(): string { return "<native fn>"; }
        }
        this.globals.define("read_line", read_line);

        const parse_num: LoxCallable = {
            arity(): number { return 1; },
            call(_, args): Value {
                if (typeof args[0] !== "string") return null;
                const parsed = parseFloat(args[0]);
                if (Number.isNaN(parsed)) return null;
                return parsed;
            },
            toString(): string { return "<native fn>"; }
        }
        this.globals.define("parse_num", parse_num);
    }

    visitCommaExpr(expr: Comma): Value {
        this.evaluate(expr.left);
        return this.evaluate(expr.right);
    }

    visitTernaryExpr(expr: Ternary): Value {
        const cond = this.evaluate(expr.cond);
        if (isTruthy(cond))
            return this.evaluate(expr.truthy);
        else
            return this.evaluate(expr.falsey);
    }

    visitLiteralExpr(expr: Literal): Value {
        return expr.value;
    }

    visitLogicalExpr(expr: Logical): Value {
        let left = this.evaluate(expr.left);

        if (expr.operator.type === TokenType.OR) {
            if (isTruthy(left)) return left;
        } else {
            if (!isTruthy(left)) return left;
        }

        return this.evaluate(expr.right);
    }

    visitSetExpr(expr: SetExpr): Value {
        const object = this.evaluate(expr.object);

        if (!(object instanceof LoxInstance)) {
            throw new RuntimeError(expr.name, "Only instances have fields.");
        }

        const value = this.evaluate(expr.value);
        object.set(expr.name, value);
        return value;
    }

    visitSuperExpr(expr: Super): Value {
        const distance = this.locals.get(expr) as number;
        const superclass = this.environment.getAt(distance, "super") as LoxClass;
        const object = this.environment.getAt(distance - 1, "this") as LoxInstance;

        const method = superclass.findMethod(expr.method.lexeme) as LoxFunction;

        if (method === null) {
            throw new RuntimeError(expr.method, "Undefined property '" + expr.method.lexeme + "'.");
        }

        return method.bind(object);
    }

    visitThisExpr(expr: This): Value {
        return this.lookUpVariable(expr.keyword, expr);
    }

    visitGroupingExpr(expr: Grouping): Value {
        return this.evaluate(expr.expression);
    }

    checkNumberOperand(operator: Token, operand: Value) {
        if (typeof operand === "number") return;
        throw new RuntimeError(operator, "Operand must be a number.");
    }

    checkNumberOperands(operator: Token, left: Value, right: Value) {
        if (typeof left === "number" && typeof right === "number") return;
        throw new RuntimeError(operator, "Operands must be a numbers.");
    }

    visitUnaryExpr(expr: Unary): Value {
        const right = this.evaluate(expr.right);

        switch (expr.operator.type) {
            case TokenType.BANG:
                return !isTruthy(right);
            case TokenType.MINUS:
                this.checkNumberOperand(expr.operator, right);
                return -Number(right);
        }

        return null;
    }

    evaluate(expr: Expr): Value {
        return expr.accept(this);
    }

    execute(stmt: Stmt): Value | undefined {
        return stmt.accept(this);
    }

    resolve(expr: Expr, depth: number) {
        this.locals.set(expr, depth);
    }

    executeBlock(statements: Stmt[], environment: Environment): Value | undefined {
        const previous = this.environment;
        let last_result = undefined;

        try {
            this.environment = environment;

            for (const statement of statements) {
                last_result = this.execute(statement);
            }
        } finally {
            this.environment = previous;
        }


        return last_result;
    }

    visitClassStmt(stmt: Class): Value {
        let superclass = null;
        if (stmt.superclass !== null) {
            superclass = this.evaluate(stmt.superclass);
            if (!(superclass instanceof LoxClass)) {
                throw new RuntimeError(stmt.superclass.name, "Superclass must be a class.");
            }
        }

        this.environment.define(stmt.name.lexeme, null);

        if (stmt.superclass !== null) {
            this.environment = new Environment(this.environment);
            this.environment.define("super", superclass);
        }

        const methods = new Map<string, LoxFunction>();
        for (const method of stmt.methods) {
            const func = new LoxFunction(method, this.environment, method.name.lexeme === "init");
            methods.set(method.name.lexeme, func);
        }

        const klass = new LoxClass(stmt.name.lexeme, superclass, methods);

        if (superclass !== null) {
            this.environment = this.environment.enclosing as Environment;
        }

        this.environment.assign(stmt.name, klass);
        return null;
    }

    visitBlockStmt(stmt: Block): Value | undefined {
        return this.executeBlock(stmt.statements, new Environment(this.environment));
    }

    visitExpressionStmt(stmt: Expression): Value {
        return this.evaluate(stmt.expression);
    }

    visitFuncStmt(stmt: Func): Value | undefined {
        const func = new LoxFunction(stmt, this.environment, false);
        this.environment.define(stmt.name.lexeme, func);
        return undefined;
    }

    visitIfStmt(stmt: If): undefined {
        if (isTruthy(this.evaluate(stmt.condition))) {
            this.execute(stmt.then_branch);
        } else if (stmt.else_branch !== null) {
            this.execute(stmt.else_branch);
        }
        return undefined;
    }


    visitPrintStmt(stmt: Print): undefined {
        const value = this.evaluate(stmt.expression);
        printSync(stringify(value));
        return undefined;
    }

    visitReturnStmt(stmt: Return): undefined {
        let value = null;
        if (stmt.value !== null)
            value = this.evaluate(stmt.value);

        throw new ReturnException(value);
    }

    visitVarStmt(stmt: Var): undefined {
        let value = null;
        if (stmt.initializer !== null) {
            value = this.evaluate(stmt.initializer);
        }

        this.environment.define(stmt.name.lexeme, value);
        return undefined;
    }

    visitWhileStmt(stmt: While): undefined {
        while (isTruthy(this.evaluate(stmt.condition))) {
            try {
                this.execute(stmt.body);
            } catch (err: any) {
                if (err instanceof BreakException) break;
                // FIXME(sezoka): increment doesnt work for 'for' statements
                if (err instanceof ContinueException) continue;
                throw err;
            }
        }

        return undefined;
    }

    visitBreakStmt(): undefined {
        throw new BreakException;
    }

    visitContinueStmt(): undefined {
        throw new ContinueException;
    }

    visitAssignExpr(expr: Assign): Value {
        const value = this.evaluate(expr.value);

        let distance = this.locals.get(expr);
        if (distance === undefined) {
            this.globals.assign(expr.name, value);
        } else {
            this.environment.assignAt(distance, expr.name, value);
        }

        return value;
    }

    visitVariableExpr(expr: Variable): Value {
        return this.lookUpVariable(expr.name, expr);
    }

    lookUpVariable(name: Token, expr: Expr) {
        const distance = this.locals.get(expr);
        if (distance !== undefined) {
            return this.environment.getAt(distance, name.lexeme);
        } else {
            return this.globals.get(name);
        }
    }

    visitBinaryExpr(expr: Binary): Value {
        let left = this.evaluate(expr.left);
        let right = this.evaluate(expr.right);

        switch (expr.operator.type) {
            case TokenType.GREATER:
                this.checkNumberOperands(expr.operator, left, right);
                return (left as number) > (right as unknown as number);
            case TokenType.GREATER_EQUAL:
                this.checkNumberOperands(expr.operator, left, right);
                return (left as number) >= (right as unknown as number);
            case TokenType.LESS:
                this.checkNumberOperands(expr.operator, left, right);
                return (left as number) < (right as unknown as number);
            case TokenType.LESS_EQUAL:
                this.checkNumberOperands(expr.operator, left, right);
                return (left as number) <= (right as unknown as number);
            case TokenType.MINUS:
                this.checkNumberOperands(expr.operator, left, right);
                return (left as number) - (right as number);
            case TokenType.PLUS:
                if (typeof left === "number" && typeof right === "number") {
                    return left + right;
                }
                if (typeof left === "string" && typeof right === "string") {
                    return left + right;
                }
                throw new RuntimeError(expr.operator, "Operands must be two numbers or two strings.");
            case TokenType.PERCENT:
                this.checkNumberOperands(expr.operator, left, right);
                if (right === 0) {
                    throw new RuntimeError(expr.operator, "Division by zero.");
                }
                return (left as number) % (right as number);
            case TokenType.DIV:
                this.checkNumberOperands(expr.operator, left, right);
                if (right === 0) {
                    throw new RuntimeError(expr.operator, "Division by zero.");
                }
                return Math.trunc((left as number) / (right as number));
            case TokenType.SLASH:
                this.checkNumberOperands(expr.operator, left, right);
                if (right === 0) {
                    throw new RuntimeError(expr.operator, "Division by zero.");
                }
                return (left as number) / (right as number);
            case TokenType.STAR:
                this.checkNumberOperands(expr.operator, left, right);
                return (left as number) * (right as number);
            case TokenType.BANG_EQUAL:
                return !isEqual(left, right);
            case TokenType.EQUAL_EQUAL:
                return isEqual(left, right);
        }

        return null;
    }

    visitCallExpr(expr: Call): Value {
        let callee = this.evaluate(expr.callee);

        const args = [];
        for (const argument of expr.args) {
            args.push(this.evaluate(argument));
        }

        if (!isCallable(callee)) {
            throw new RuntimeError(expr.paren, "Can only call functions and classes.");
        }

        const func: LoxCallable = callee as LoxCallable;
        if (args.length !== func.arity()) {
            throw new RuntimeError(expr.paren, "Expected " + func.arity() + " arguments but got " + args.length + ".");
        }

        return func.call(this, args);
    }

    visitGetExpr(expr: Get): Value {
        const object = this.evaluate(expr.object);
        if (object instanceof LoxInstance) {
            return object.get(expr.name);
        }

        throw new RuntimeError(expr.name, "Only instances have properties.");
    }

    interpret(statements: Stmt[]): Value | undefined {
        let last_result = undefined;
        try {
            for (const statement of statements) {
                last_result = this.execute(statement);
            }
        } catch (error: any) {
            if (error instanceof RuntimeError) {
                runtimeError(error);
            }
        }
        return last_result;
    }
}
