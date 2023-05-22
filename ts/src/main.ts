import fs from "fs";
import * as readline from "readline/promises";
import { stdin, stdout } from "process"
import { Scanner } from "./scanner.js";
import { TokenType } from "./token_type.js";
import { Token } from "./token.js";
import { Parser } from "./parser.js";
import { RuntimeError } from "./runtime_error.js";
import { Interpreter, stringify } from "./interpreter.js";
import { Resolver } from "./resolver.js";

let had_error = false;
let had_runtime_error = false;
let interpreter = new Interpreter();

function run(src: string, repl_mode = false): void {
    const scanner = new Scanner(src);
    const tokens = scanner.scanTokens();
    const parser = new Parser(tokens);
    const statements = parser.parse();

    if (had_error) return;

    const resolver = new Resolver(interpreter);
    resolver.resolveStmt(statements);

    if (had_error) return;

    const result = interpreter.interpret(statements);
    if (repl_mode && result !== undefined) {
        console.log(stringify(result));
    }
}

export function error(line: number, message: string): void;
export function error(token: Token, message: string): void;
export function error(a: any, message: string) {
    if (typeof a === "number") {
        const line = a;
        report(line, "", message);
        return;
    }

    const token = a;
    if (token.type === TokenType.EOF) {
        report(token.line, " at end", message);
    }
    report(token.line, " at '" + token.lexeme + "'", message);
}

export function runtimeError(error: RuntimeError) {
    console.error(`${error.message}\n[line ${error.token.line}]`);
    had_runtime_error = true;
}

export function report(line: number, where: string, msg: string) {
    had_error = true;
    console.error(`[line: ${line}] Error ${where}: ${msg}`);
}

async function runFile(path: string) {
    try {
        const src = fs.readFileSync(path).toString();
        run(src);
        if (had_error) process.exit(65);
        if (had_runtime_error) process.exit(70);
    } catch (err) {
        console.error(`cannot read file "${path}", msg: ${err}`);
    }
}

async function runPrompt() {
    const rl = readline.createInterface(stdin, stdout);
    for (; ;) {
        const src = await rl.question("> ");
        run(src, true);
        had_error = false;
    }
}

async function main() {
    const args = process.argv;
    if (3 < args.length) {
        console.info("Usage: tlox [script]");
        process.exit(64);
    } else if (args.length == 3) {
        await runFile(args[2]);
    } else {
        await runPrompt();
    }

    if (had_error) process.exit(65);

    process.exit(0);
}

main();
