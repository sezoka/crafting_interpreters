package main

import "core:fmt"

DEBUG_ENABLED :: true

disassemble_chunk :: proc(c: Chunk, name: string) {
  fmt.printf("== %s ==\n", name);

  for offset: uint = 0; offset < len(c.code); {
    offset = disassemble_instruction(c, offset)
  }
}

disassemble_instruction :: proc(c: Chunk, offset: uint) -> uint {
  fmt.printf("%4d ", offset)

  if offset > 0 &&
      c.lines[offset] == c.lines[offset - 1] {
    fmt.printf("   | ");
  } else {
    fmt.printf("% 4d ", c.lines[offset]);
  }

  instruction := Op_Code(c.code[offset])
  switch instruction {
  case .Return:
    return simple_instruction("OP_RETURN", offset)
  case .Constant:
    return constant_instruction("OP_CONSTANT", c, offset)
  case .Negate:
    return simple_instruction("OP_NEGATE", offset)
  case .Add:
    return simple_instruction("OP_ADD", offset)
  case .Subtract:
    return simple_instruction("OP_SUBTRACT", offset)
  case .Multiply:
    return simple_instruction("OP_MULTIPLY", offset)
  case .Divide:
    return simple_instruction("OP_DIVIDE", offset)
  }
  return offset + 1
}

constant_instruction :: proc(name: string, c: Chunk, offset: uint) -> uint {
  constant_id := c.code[offset + 1]
  fmt.printf("% -16s % 4d '", name, constant_id)
  print_value(c.constants[constant_id])
  fmt.printf("'\n")
  return offset + 2
}

simple_instruction :: proc(name: string, offset: uint) -> uint {
  fmt.printf("%s\n", name)
  return offset + 1
}
