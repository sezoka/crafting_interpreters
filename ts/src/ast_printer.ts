import { Binary, Comma, Expr, Grouping, Literal, Ternary, Unary, Visitor } from "./Expr.js";
import { Token } from "./token.js";
import { TokenType } from "./token_type.js";


export class AstPrinter implements Visitor<string> {
    parenthesize(name: string, ...exprs: Expr[]): string {
        const builder: string[] = [];
        builder.push("(");
        builder.push(name);
        for (const expr of exprs) {
            builder.push(" ");
            builder.push(expr.accept(this));
        }
        builder.push(")");
        return builder.join("");
    }

    print(expr: Expr): string {
        return expr.accept(this);
    }

    visitBinaryExpr(expr: Binary): string {
        return this.parenthesize(expr.operator.lexeme,
            expr.left, expr.right);
    }

    visitGroupingExpr(expr: Grouping): string {
        return this.parenthesize("group", expr.expression);
    }

    visitLiteralExpr(expr: Literal): string {
        if (expr.value == null) return "nil";
        return expr.value.toString();
    }

    visitUnaryExpr(expr: Unary): string {
        return this.parenthesize(expr.operator.lexeme, expr.right);
    }

    visitCommaExpr(expr: Comma): string {
        return this.parenthesize(",", expr.left, expr.right);
    }

    visitTernaryExpr(expr: Ternary): string {
        return this.parenthesize("?", expr.cond, expr.truthy, expr.falsey);
    }

}

export function test() {
    const expression = new Binary(
        new Unary(
            new Token(TokenType.MINUS, "-", null, 1),
            new Literal(123)),
        new Token(TokenType.STAR, "*", null, 1),
        new Grouping(
            new Literal(45.67)));

    console.log(new AstPrinter().print(expression));
}

