import { Value } from "./Expr";
import { Interpreter } from "./interpreter";


export interface LoxCallable {
    arity(): number;
    call(interpreter: Interpreter, args: Value[]): Value;
    toString(): string;
}

export function isCallable(val: Value): boolean {
    if (val instanceof Object) {
        return (val as any).call !== undefined;
    }
    return false;
}
