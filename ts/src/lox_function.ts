import { Environment } from "./environment.js";
import { Value } from "./Expr.js";
import { Interpreter } from "./interpreter.js";
import { LoxCallable } from "./lox_callable.js";
import { LoxInstance } from "./lox_instance.js";
import { ReturnException } from "./return.js";
import { Func } from "./Stmt.js";


export class LoxFunction implements LoxCallable {
    declaration: Func;
    closure: Environment;
    is_initializer: boolean;

    constructor(declaration: Func, closure: Environment, is_initializer: boolean) {
        this.closure = closure;
        this.declaration = declaration;
        this.is_initializer = is_initializer;
    }

    bind(instance: LoxInstance): LoxFunction {
        const environment = new Environment(this.closure);
        environment.define("this", instance);
        return new LoxFunction(this.declaration, environment, this.is_initializer);
    }

    call(interpreter: Interpreter, args: Value[]): Value {
        const environment = new Environment(this.closure);
        for (let i = 0; i < this.declaration.params.length; i += 1) {
            environment.define(this.declaration.params[i].lexeme, args[i]);
        }

        try {
            interpreter.executeBlock(this.declaration.body, environment);
        } catch (return_value: any) {
            if (return_value instanceof ReturnException) {
                if (this.is_initializer) return this.closure.getAt(0, "this");
                return return_value.value;
            }
            throw return_value;
        }

        if (this.is_initializer) return this.closure.getAt(0, "this");
        return null;
    }

    arity(): number {
        return this.declaration.params.length;
    }

    toString(): string {
        return "<fn " + this.declaration.name.lexeme + ">";
    }
}
