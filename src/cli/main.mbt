/// Interactive Shell CLI

///|
fn main {
  let ctx = @posix.PosixContext::default()
  let shell = @shell.Shell::new(ctx)

  write_stdout("MoonBit Shell\n")
  write_stdout("Type 'exit' to quit\n\n")

  let mut running = true
  while running {
    write_stdout("$ ")
    match read_line() {
      None => {
        write_stdout("\n")
        running = false
      }
      Some(line) => {
        let trimmed = line.trim().to_string()
        if trimmed == "exit" || trimmed == "exit 0" {
          running = false
        } else if trimmed.length() > 0 {
          let result = shell.exec_line(trimmed)
          if not(result.stdout.is_empty()) {
            write_stdout(result.stdout)
          }
          if not(result.stderr.is_empty()) {
            write_stdout(result.stderr)
          }
        }
      }
    }
  }
}
