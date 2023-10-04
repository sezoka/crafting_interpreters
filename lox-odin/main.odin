package main

import "core:fmt"

main :: proc() {
  vm : VM
  init_vm(&vm)

  c := init_chunk()

  constant_id := add_constant(&c, 1.2)
  write_chunk(&c, u8(Op_Code.Constant), 123)
  write_chunk(&c, constant_id, 123)

  constant_id = add_constant(&c, 3.4);
  write_chunk(&c, u8(Op_Code.Constant), 123);
  write_chunk(&c, constant_id, 123);

  write_chunk(&c, u8(Op_Code.Add), 123);

  constant_id = add_constant(&c, 5.6);
  write_chunk(&c, u8(Op_Code.Constant), 123);
  write_chunk(&c, constant_id, 123);

  write_chunk(&c, u8(Op_Code.Divide), 123);
  write_chunk(&c, u8(Op_Code.Negate), 123)

  write_chunk(&c, u8(Op_Code.Return), 123)

  defer free_chunk(&c)

  interpret(&vm, c)
}
