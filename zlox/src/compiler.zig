const std = @import("std");
const chunk = @import("chunk.zig");
const scanner = @import("scanner.zig");

const Parser = struct {
    current: scanner.Token,
    previous: scanner.Token,
    panic_mode: bool,
    had_error: bool,
    scanner: *scanner.Scanner,
    compiling_chunk: *chunk.Chunk,
};

fn init_parser(s: *scanner.Scanner, ch: *chunk.Chunk) Parser {
    return .{
        .current = undefined,
        .previous = undefined,
        .had_error = false,
        .panic_mode = false,
        .scanner = s,
        .compiling_chunk = ch,
    };
}

pub fn compile(alloc: std.mem.Allocator, source: []const u8) !chunk.Chunk {
    var ch = chunk.init(alloc);
    var s = scanner.init_scanner(source);
    var parser = init_parser(&s, &ch);
    advance(&parser);
    // expression();
    consume(&parser, .Eof, "Expect end of expression");

    if (parser.had_error) {
        return error.ParserHadError;
    }

    return ch;
}

fn emit_byte(p: *Parser, byte: u8) void {
    chunk.append_byte(p.chunk, current_chunk(p), byte, p.previous.line);
}

fn current_chunk(p: *Parser) *chunk.Chunk {
    return p.compiling_chunk;
}

fn consume(p: *Parser, kind: scanner.Token_Kind, message: []const u8) void {
    if (p.current.kind == kind) {
        advance(p);
        return;
    }

    error_at_current(p, message);
}

fn advance(p: *Parser) void {
    p.previous = p.current;

    while (true) {
        p.current = scanner.scan_token(p.scanner);
        if (p.current.kind != .Error) break;

        error_at_current(p, p.current.literal);
    }
}

fn error_at_current(p: *Parser, message: []const u8) void {
    error_at(p, p.current, message);
}

fn error_(p: *Parser, message: []const u8) void {
    error_at(p, p.previous, message);
}

fn error_at(p: *Parser, token: scanner.Token, message: []const u8) void {
    if (p.panic_mode) return;
    p.panic_mode = true;

    const stderr = std.io.getStdErr().writer();

    stderr.print("[line {d}] Error", .{token.literal}) catch {};

    if (token.kind == .Eof) {
        stderr.print(" at end", .{}) catch {};
    } else if (token.kind == .Error) {
        //
    } else {
        stderr.print(" at '{s}'", .{token.literal}) catch {};
    }

    stderr.print(": {s}\n", .{message}) catch {};
    p.had_error = true;
}
