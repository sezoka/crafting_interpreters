import { Value } from "./Expr.js";
import { Interpreter } from "./interpreter.js";
import { LoxCallable } from "./lox_callable.js";
import { LoxFunction } from "./lox_function.js";
import { LoxInstance } from "./lox_instance.js";


export class LoxClass implements LoxCallable {
    name: string;
    methods: Map<string, LoxFunction>;
    superclass: LoxClass | null;

    constructor(name: string, superclass: LoxClass | null, methods: Map<string, LoxFunction>) {
        this.name = name;
        this.superclass = superclass;
        this.methods = methods;
    }

    findMethod(name: string): LoxFunction | null {
        if (this.methods.has(name)) {
            return this.methods.get(name)!;
        }

        if (this.superclass !== null) {
            return this.superclass.findMethod(name);
        }

        return null;
    }

    toString(): string {
        return this.name;
    }

    call(interpreter: Interpreter, args: Value[]): Value {
        const instance = new LoxInstance(this);
        const initializer = this.findMethod("init");
        if (initializer !== null) {
            initializer.bind(instance).call(interpreter, args);
        }

        return instance
    }

    arity(): number {
        const initializer = this.findMethod("init");
        if (initializer === null) return 0;
        return initializer.arity();
    }
}
