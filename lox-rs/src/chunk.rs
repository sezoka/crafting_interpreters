use crate::value::Value;

pub enum OpCode {
    Return,
    Constant(u8),
}

pub struct Chunk {
    pub code: Vec<OpCode>,
    pub constants: Vec<Value>,
    pub lines: Vec<u16>,
}

impl Chunk {
    pub fn new() -> Chunk {
        Chunk {
            code: Vec::new(),
            constants: Vec::new(),
            lines: Vec::new(),
        }
    }

    pub fn write(&mut self, code: OpCode, line: u16) {
        self.code.push(code);
        self.lines.push(line);
    }

    pub fn add_constant(&mut self, val: Value) -> u8 {
        self.constants.push(val);
        (self.constants.len() - 1) as u8
    }
}
