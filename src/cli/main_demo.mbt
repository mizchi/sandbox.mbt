/// Shell CLI Demo (wasm-gc target)

///|
fn main {
  let ctx = @posix.PosixContext::default()
  let shell = @shell.Shell::new(ctx)

  // Demo: run some example commands
  println("MoonBit Shell Demo")
  println("==================")
  println("")

  // Basic commands
  run_demo(shell, "echo Hello, World!")
  run_demo(shell, "pwd")

  // Logical operators
  run_demo(shell, "true && echo 'Success!'")
  run_demo(shell, "false || echo 'Fallback!'")

  // Sequence
  run_demo(shell, "echo first; echo second; echo third")

  // Variables
  run_demo(shell, "NAME=MoonBit; echo Hello, $NAME!")

  // Exit code
  run_demo(shell, "false; echo Exit code: $?")

  // If statement
  run_demo(shell, "if true; then echo 'Condition is true'; fi")
  run_demo(shell, "if false; then echo no; else echo 'Else branch'; fi")

  // For loop
  run_demo(shell, "for i in a b c; do echo Item: $i; done")

  // While loop (limited iterations)
  run_demo(
    shell,
    "COUNT=0; while test $COUNT -lt 3; do echo Count: $COUNT; COUNT=3; done",
  )

  // Case statement
  run_demo(
    shell,
    "case hello in hello) echo 'Matched hello';; *) echo 'No match';; esac",
  )

  // Test command
  run_demo(shell, "test -z \"\" && echo 'Empty string'")
  run_demo(shell, "test 5 -gt 3 && echo '5 > 3'")
  run_demo(shell, "[ foo = foo ] && echo 'Strings equal'")

  // File operations
  run_demo(shell, "mkdir /demo")
  run_demo(shell, "touch /demo/file.txt")
  run_demo(shell, "ls /demo")

  // Complex example
  run_demo(shell, "if test -d /demo; then echo 'Directory exists'; ls /demo; fi")

  println("")
  println("Demo complete!")
}

///|
fn run_demo(shell : @shell.Shell, cmd : String) -> Unit {
  println("$ " + cmd)
  let result = shell.exec_line(cmd)
  if not(result.stdout.is_empty()) {
    print_output(result.stdout)
  }
  if not(result.stderr.is_empty()) {
    print_output("[stderr] " + result.stderr)
  }
  println("")
}

///|
fn print_output(s : String) -> Unit {
  // Remove trailing newline for cleaner output
  let trimmed = s.trim()
  for line in trimmed.split("\n") {
    println("  " + line.to_string())
  }
}
