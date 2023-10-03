use vm::VM;

mod chunk;
mod compiler;
mod debug;
mod scaner;
mod value;
mod vm;

fn main() {
    let mut v = VM::new();
    let args = std::env::args().skip(1).collect::<Vec<_>>();
    if args.len() == 0 {
        repl(&mut v);
    } else if args.len() == 1 {
        run_file(&mut v, &args[0]);
    } else {
        eprintln!("Usage: clox [path]\n");
    }
}

fn repl(v: &mut VM) {
    let stdin = std::io::stdin();
    let mut input = String::new();
    loop {
        input.clear();
        match stdin.read_line(&mut input) {
            Ok(n) => {
                if n == 0 {
                    println!();
                    return;
                }
            }
            Err(msg) => {
                eprintln!("{}", msg);
                return;
            }
        }

        v.interpret(&input);
    }
}

fn run_file(v: &mut VM, path: &str) {
    match std::fs::read_to_string(path) {
        Ok(src) => {
            let result = v.interpret(&src);
            // eprintln!("{:?}", result);
            return;
        }
        Err(_) => eprintln!("Could not open file \"{}\".\n", path),
    }
}
