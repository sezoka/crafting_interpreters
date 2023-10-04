package main

import "core:mem"
import "core:fmt"

STACK_MAX :: 256

VM :: struct {
  chunk: Chunk,
  ip: ^u8,
  stack: [STACK_MAX]Value,
  stack_top: ^Value,
}

Interpret_Result :: enum {
  Ok,
  Runtime_Error,
  Compile_Error,
}

init_vm :: proc(vm: ^VM) {
  reset_stack(vm)
}

free_vm :: proc(vm: ^VM) {
}

interpret :: proc(vm: ^VM, c: Chunk) -> Interpret_Result {
  vm.chunk = c
  vm.ip = &c.code[0]
  return run(vm)
}

run :: proc(vm: ^VM) -> Interpret_Result {
  for {
    when DEBUG_ENABLED {
      fmt.printf("          ")
      for slot := &vm.stack[0]; slot < vm.stack_top; slot = mem.ptr_offset(slot, 1) {
        fmt.printf("[ ");
        print_value(slot^);
        fmt.printf(" ]");
      }
      fmt.printf("\n");
      disassemble_instruction(vm.chunk, uint(mem.ptr_sub(vm.ip, &vm.chunk.code[0])))
    }

    switch instr := read_instr(vm); instr {
    case .Return:
      print_value(stack_pop(vm))
      fmt.println()
      return .Ok
    case .Constant:
      constant := read_constant(vm)
      stack_push(vm, constant)
    case .Negate:
      stack_push(vm, -stack_pop(vm))
    case .Add:
      b := stack_pop(vm)
      a := stack_pop(vm)
      stack_push(vm, a + b)
    case .Subtract:
      b := stack_pop(vm)
      a := stack_pop(vm)
      stack_push(vm, a - b)
    case .Multiply:
      b := stack_pop(vm)
      a := stack_pop(vm)
      stack_push(vm, a * b)
    case .Divide:
      b := stack_pop(vm)
      a := stack_pop(vm)
      stack_push(vm, a / b)
    }
  }

  return .Ok
}

read_instr :: proc(vm: ^VM) -> Op_Code {
  return Op_Code(read_byte(vm))
}

read_byte :: proc(vm: ^VM) -> u8 {
  byte := vm.ip^
  vm.ip = mem.ptr_offset(vm.ip, 1)
  return byte
}

read_constant :: proc(vm: ^VM) -> Value {
  return vm.chunk.constants[read_byte(vm)]
}

reset_stack :: proc(vm: ^VM) {
  vm.stack_top = &vm.stack[0]
}

stack_push :: proc(vm: ^VM, v: Value) {
  vm.stack_top^ = v
  vm.stack_top = mem.ptr_offset(vm.stack_top, 1)
}

stack_pop :: proc(vm: ^VM) -> Value {
  vm.stack_top = mem.ptr_offset(vm.stack_top, -1)
  return vm.stack_top^
}
