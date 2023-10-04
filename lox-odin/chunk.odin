package main

Op_Code :: enum {
  Return,
  Constant,
}

Chunk :: struct {
  code: [dynamic]u8,
  constants: [dynamic]Value,
  lines: [dynamic]u16
}

init_chunk :: proc() -> Chunk {
  return Chunk {};
}

write_chunk :: proc(c: ^Chunk, byte: u8, line: u16) {
  append(&c.code, byte)
  append(&c.lines, line)
}

add_constant :: proc(c: ^Chunk, v: Value) -> u8 {
  append(&c.constants, v)
  return u8(len(c.constants) - 1);
}

free_chunk :: proc(c: ^Chunk) {
  delete(c.code)
  delete(c.constants)
}
