package main

import "core:fmt"

main :: proc() {
  c := init_chunk()

  constant_id := add_constant(&c, 1.2)
  write_chunk(&c, u8(Op_Code.Constant), 123)
  write_chunk(&c, constant_id, 123)

  write_chunk(&c, u8(Op_Code.Return), 123)
  defer free_chunk(&c)

  disassemble_chunk(c, "test chunk")
}
