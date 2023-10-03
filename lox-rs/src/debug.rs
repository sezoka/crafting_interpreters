use crate::{
    chunk::{Chunk, OpCode},
    value,
};

pub const DEBUG_ENABLED: bool = true;

pub fn disassemble_chunk(ch: &Chunk, name: &str) {
    eprintln!("== {} ==", name);

    let mut offset = 0;
    while offset < ch.code.len() {
        offset = disassemble_instruction(ch, offset);
    }
}

pub fn disassemble_instruction(ch: &Chunk, offset: usize) -> usize {
    eprint!("{:04} ", offset);
    if 0 < offset && ch.lines[offset] == ch.lines[offset - 1] {
        eprint!("   | ");
    } else {
        eprint!("{:4} ", ch.lines[offset]);
    }
    let instr = &ch.code[offset];
    match instr {
        OpCode::Return => simple_instruction("OP_RETURN", offset),
        OpCode::Constant(id) => constant_instruction("OP_CONSTANT", &ch, *id, offset),
        OpCode::Negate => simple_instruction("OP_NEGATE", offset),
        OpCode::Add => simple_instruction("OP_ADD", offset),
        OpCode::Subtract => simple_instruction("OP_SUBTRACT", offset),
        OpCode::Multiply => simple_instruction("OP_MULTIPLY", offset),
        OpCode::Divide => simple_instruction("OP_DIVIDE", offset),
    }
}

fn constant_instruction(name: &str, ch: &Chunk, constant_id: u8, offset: usize) -> usize {
    eprint!("{:-16} {:4} '", name, constant_id);
    value::eprint_value(ch.constants[constant_id as usize]);
    eprintln!("'");
    return offset + 1;
}

fn simple_instruction(name: &str, offset: usize) -> usize {
    eprintln!("{}", name);
    return offset + 1;
}
