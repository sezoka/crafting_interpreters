pub type Value = f32;

pub fn print_value(val: Value) {
    print!("{:.2}", val);
}

pub fn eprint_value(val: Value) {
    eprint!("{:.2}", val);
}
