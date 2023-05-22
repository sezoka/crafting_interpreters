import { Value } from "./Expr";


export class ReturnException {
    value: Value;

    constructor(value: Value) {
        this.value = value;
    }
}
