use crate::{
    chunk::{Chunk, OpCode},
    debug,
    value::{self, Value},
};

macro_rules! binary_op {
    ( $vm:expr, $op:tt ) => {
        {
            let b = $vm.stack_pop();
            let a = $vm.stack_pop();
            $vm.stack_push(a $op b);
        }
    };
}

pub enum InterpretError {
    Runtime,
    Compile,
}

pub type InterpretResult = std::result::Result<(), InterpretError>;

const STACK_MAX: usize = 256;

pub struct VM {
    chunk: Chunk,
    ip: usize,
    stack: [Value; STACK_MAX],
    stack_top: usize,
}

impl VM {
    pub fn new() -> VM {
        return VM {
            chunk: Chunk::new(),
            ip: 0,
            stack: [0.0; STACK_MAX],
            stack_top: 0,
        };
    }

    pub fn interpret(&mut self, ch: Chunk) -> InterpretResult {
        self.chunk = ch;
        self.ip = 0;
        self.stack_top = 0;
        self.stack = [0.0; STACK_MAX];
        return self.run();
    }

    fn run(&mut self) -> InterpretResult {
        loop {
            if debug::DEBUG_ENABLED {
                eprint!("          ");
                for i in 0..self.stack_top {
                    eprint!("[ ");
                    value::eprint_value(self.stack[i]);
                    eprint!(" ]");
                }
                eprintln!();
                debug::disassemble_instruction(&self.chunk, self.ip);
            }

            let instr = self.read_instr();
            match instr {
                OpCode::Return => {
                    value::print_value(self.stack_pop());
                    println!();
                    return Ok(());
                }
                OpCode::Constant(id) => {
                    let constant = self.chunk.constants[id as usize];
                    self.stack_push(constant);
                }
                OpCode::Negate => {
                    let val = -self.stack_pop();
                    self.stack_push(val);
                }
                OpCode::Add => binary_op!(self, +),
                OpCode::Subtract => binary_op!(self, -),
                OpCode::Multiply => binary_op!(self, *),
                OpCode::Divide => binary_op!(self, /),
            }
        }
    }

    fn read_instr(&mut self) -> OpCode {
        self.ip += 1;
        return self.chunk.code[self.ip - 1];
    }

    fn stack_push(&mut self, v: Value) {
        self.stack[self.stack_top] = v;
        self.stack_top += 1;
    }

    fn stack_pop(&mut self) -> Value {
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }
}
