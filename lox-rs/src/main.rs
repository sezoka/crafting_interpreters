use chunk::{Chunk, OpCode};
use vm::VM;

mod chunk;
mod debug;
mod value;
mod vm;

fn main() {
    let mut chunk = Chunk::new();
    let mut constant_id = chunk.add_constant(1.2);
    chunk.write(OpCode::Constant(constant_id), 123);

    // writeChunk(&chunk, OP_DIVIDE, 123);

    constant_id = chunk.add_constant(3.4);
    chunk.write(OpCode::Constant(constant_id), 123);

    chunk.write(OpCode::Add, 123);

    constant_id = chunk.add_constant(5.6);
    chunk.write(OpCode::Constant(constant_id), 123);

    chunk.write(OpCode::Divide, 123);

    chunk.write(OpCode::Negate, 123);
    chunk.write(OpCode::Return, 123);

    // debug::disassemble_chunk(&chunk, "test chunk");

    let mut v = VM::new();
    v.interpret(chunk);
}
