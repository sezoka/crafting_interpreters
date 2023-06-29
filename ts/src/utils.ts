import fs from "fs";

export function readLine() {
    const buffer = Buffer.alloc(1024);
    const stdin = fs.openSync("/dev/stdin", "r", 0o666);
    fs.readSync(stdin, buffer, 0, 1024, null);
    const line = buffer.toString('utf8');
    fs.closeSync(stdin);
    return line.split("\n")[0];
}

export function printSync(str: string) {
    const stdout = fs.openSync("/dev/stdout", "w", 0o666);
    fs.writeSync(stdout, str + "\n");
    fs.closeSync(stdout);
}
