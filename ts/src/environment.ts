import { Value } from "./Expr";
import { RuntimeError } from "./runtime_error.js";
import { Token } from "./token";

export class Environment {
    values: Map<string, Value> = new Map();
    enclosing: Environment | null;

    constructor(enclosing?: Environment) {
        this.enclosing = enclosing ?? null;
    }

    define(name: string, value: Value) {
        this.values.set(name, value);
    }

    getAt(distance: number, name: string): Value {
        // NOTE(sezoka): we verified that this environment exists at resolve stage
        return this.ancestor(distance).values.get(name) as Value;
    }

    assignAt(distance: number, name: Token, value: Value): void {
        this.ancestor(distance).values.set(name.lexeme, value);
    }

    ancestor(distance: number): Environment {
        let environment: Environment = this;
        for (let i = 0; i < distance; i += 1) {
            environment = environment.enclosing as Environment;
        }

        return environment;
    }

    get(name: Token): Value {
        if (this.values.has(name.lexeme))
            return this.values.get(name.lexeme) as Value;

        if (this.enclosing !== null)
            return this.enclosing.get(name);

        throw new RuntimeError(name, "undefined variable '" + name.lexeme + "'.");
    }

    assign(name: Token, value: Value) {
        if (this.values.has(name.lexeme)) {
            this.values.set(name.lexeme, value);
            return;
        }

        if (this.enclosing !== null) {
            this.enclosing.assign(name, value);
            return;
        }

        throw new RuntimeError(name, "Undefined variable '" + name.lexeme + "'.");
    }
}
