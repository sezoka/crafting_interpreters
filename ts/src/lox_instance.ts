import { Value } from "./Expr.js";
import { LoxClass } from "./lox_class.js";
import { RuntimeError } from "./runtime_error.js";
import { Token } from "./token.js";


export class LoxInstance {
    klass: LoxClass;
    fields = new Map<String, Value>();

    constructor(klass: LoxClass) {
        this.klass = klass;
    }

    toString(): string {
        return this.klass.name + " instance";
    }

    get(name: Token): Value {
        if (this.fields.has(name.lexeme)) {
            return this.fields.get(name.lexeme) as Value;
        }

        const method = this.klass.findMethod(name.lexeme);
        if (method !== null) return method.bind(this);

        throw new RuntimeError(name, "Undefined property '" + name.lexeme + "'.");
    }

    set(name: Token, value: Value): void {
        this.fields.set(name.lexeme, value);
    }
}
