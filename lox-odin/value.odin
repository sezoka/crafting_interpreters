package main

import "core:fmt"

Value :: f32

print_value :: proc(v: Value) {
  fmt.printf("%.1g", v)
}
