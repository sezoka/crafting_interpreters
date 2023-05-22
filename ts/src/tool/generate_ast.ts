import fs from "fs";

function defineType(lines: string[], base_name: string, class_name: string, field_list: string) {
    lines.push(`export class ${class_name} implements ${base_name} {`);

    const fields = field_list.split(", ");
    if (fields[0] != "") {
        for (const field of fields) {
            lines.push(`    ${field};`);
        }
    }
    lines.push("");
    lines.push("    accept<T>(visitor: Visitor<T>): T {");
    lines.push(`        return visitor.visit${class_name}${base_name}(this);`);
    lines.push("    }");
    lines.push("");
    lines.push(`    constructor(${field_list}) {`);
    if (fields[0] != "") {
        for (const field of fields) {
            const name = field.split(": ")[0];
            lines.push(`        this.${name} = ${name};`);
        }
    }
    lines.push("    }");
    lines.push("}");
    lines.push("");
}

function defineVisitor(lines: string[], base_name: string, types: string[]) {
    lines.push("export interface Visitor<T> {");

    for (const type of types) {
        const type_name = type.split(">")[0].trim();
        lines.push(`    visit${type_name}${base_name}: (${base_name.toLowerCase()}: ${type_name}) => T,`);
    }
    lines.push("}");
    lines.push("");
}


function defineAst(out_dir: string, base_name: string, types: string[]) {
    const path = `${out_dir}/${base_name}.ts`;
    const lines: string[] = [];

    if (base_name === "Stmt") {
        lines.push('import { Expr } from "./Expr.js";');
    }

    lines.push('import { Token } from "./token.js";');
    lines.push("");
    lines.push("export type Value = string | number | boolean | Object | null;");
    lines.push("");
    lines.push(`export interface ${base_name} {`);
    lines.push("    accept<T>(visitor: Visitor<T>): T,");
    lines.push("}");
    lines.push("");

    defineVisitor(lines, base_name, types);

    for (const type of types) {
        const class_name = type.split(">")[0].trim();
        const fields = type.split(">")[1].trim();
        defineType(lines, base_name, class_name, fields);
    }

    fs.writeFileSync(path, lines.join("\n"));
}


function main() {
    const args = process.argv;
    if (args.length !== 3) {
        console.log("Usage: generate_ast <output directory>");
        process.exit(64);
    }
    const out_dir = args[2];
    defineAst(out_dir, "Expr", [
        "Assign     > name: Token, value: Expr",
        "Binary     > left: Expr, operator: Token, right: Expr",
        "Call       > callee: Expr, paren: Token, args: Expr[]",
        "Grouping   > expression: Expr",
        "Literal    > value: Value",
        "Logical    > left: Expr, operator: Token, right: Expr",
        "Unary      > operator: Token, right: Expr",
        "Variable   > name: Token",
        "Comma      > left: Expr, right: Expr",
        "Ternary    > cond: Expr, truthy: Expr, falsey: Expr",
    ]);

    defineAst(out_dir, "Stmt", [
        "Block      > statements: Stmt[]",
        "Expression > expression: Expr",
        "Func       > name: Token, params: Token[], body: Stmt[]",
        "If         > condition: Expr, then_branch: Stmt, else_branch: Stmt | null",
        "Print      > expression: Expr",
        "Return     > keyword: Token, value: Expr | null",
        "Var        > name: Token, initializer: Expr",
        "While      > condition: Expr, body: Stmt",
        "Break      >",
        "Continue   >",
    ]);
}

main();
