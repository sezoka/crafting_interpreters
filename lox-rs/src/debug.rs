use crate::{
    chunk::{Chunk, OpCode},
    value,
};

pub fn disassemble_chunk(ch: &Chunk, name: &str) {
    println!("== {} ==", name);

    let mut offset = 0;
    while offset < ch.code.len() {
        offset = disassemble_instruction(ch, offset);
    }
}

fn disassemble_instruction(ch: &Chunk, offset: usize) -> usize {
    print!("{:04} ", offset);
    if 0 < offset && ch.lines[offset] == ch.lines[offset - 1] {
        print!("   | ");
    } else {
        print!("{:4} ", ch.lines[offset]);
    }
    let instr = &ch.code[offset];
    match instr {
        OpCode::Return => simple_instruction("OP_RETURN", offset),
        OpCode::Constant(id) => constant_instruction("OP_CONSTANT", &ch, *id, offset),
    }
}

fn constant_instruction(name: &str, ch: &Chunk, constant_id: u8, offset: usize) -> usize {
    print!("{:-16} {:4} '", name, constant_id);
    value::print_value(ch.constants[constant_id as usize]);
    println!("'");
    return offset + 1;
}

fn simple_instruction(name: &str, offset: usize) -> usize {
    println!("{}", name);
    return offset + 1;
}
