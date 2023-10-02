use chunk::{Chunk, OpCode};

mod chunk;
mod debug;
mod value;

fn main() {
    let mut chunk = Chunk::new();
    let constant_id = chunk.add_constant(1.2);
    chunk.write(OpCode::Constant(constant_id), 123);
    chunk.write(OpCode::Return, 123);

    debug::disassemble_chunk(&chunk, "test chunk");
}
