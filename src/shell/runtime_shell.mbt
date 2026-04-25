/// Minimal shell implementation (busybox-like) using runtime backend

///|
/// RuntimeShell instance using MemfsBackend
pub struct RuntimeShell {
  backend : @runtime.MemfsBackend
  mut running : Bool
}

///|
pub fn RuntimeShell::new() -> RuntimeShell {
  let backend = @runtime.MemfsBackend::new()
  backend.register_builtins()
  // Register shell-specific commands
  backend.register("exit", builtin_exit)
  backend.register("help", builtin_help)
  { backend, running: true }
}

///|
pub fn RuntimeShell::with_backend(
  backend : @runtime.MemfsBackend,
) -> RuntimeShell {
  backend.register_builtins()
  backend.register("exit", builtin_exit)
  backend.register("help", builtin_help)
  { backend, running: true }
}

///|
/// Execute a single command line
pub fn RuntimeShell::execute(self : RuntimeShell, line : String) -> ExecResult {
  let trimmed = line.trim()
  if trimmed.is_empty() || trimmed.has_prefix("#") {
    return { exit_code: 0, stdout: "", stderr: "" }
  }

  // Parse command and arguments
  let parts = parse_command_line(trimmed.to_string())
  if parts.is_empty() {
    return { exit_code: 0, stdout: "", stderr: "" }
  }
  let program = parts[0]
  let args : Array[String] = []
  for i = 1; i < parts.length(); i = i + 1 {
    args.push(parts[i])
  }

  // Check for exit command
  if program == "exit" {
    self.running = false
    return { exit_code: 0, stdout: "", stderr: "" }
  }

  // Execute command with piped output
  let cmd = @runtime.Command::new(program)
    .args(args)
    .stdout(@runtime.Stdio::Piped)
    .stderr(@runtime.Stdio::Piped)
  let result : Result[ExecResult, @runtime.ProcessError] = try {
    let proc = self.backend.spawn(cmd)
    let pid = proc.pid()
    let status = self.backend.wait(pid)
    let stdout = self.backend.read_stdout(pid)
    let stderr = self.backend.read_stderr(pid)
    Ok({ exit_code: status.code, stdout, stderr })
  } catch {
    e => Err(e)
  }
  match result {
    Ok(r) => r
    Err(e) => { exit_code: 127, stdout: "", stderr: "shell: \{e}\n" }
  }
}

///|
/// Execute multiple commands (script)
pub fn RuntimeShell::execute_script(
  self : RuntimeShell,
  script : String,
) -> Array[ExecResult] {
  let results : Array[ExecResult] = []
  for line in script.split("\n") {
    if !(self.running) {
      break
    }
    results.push(self.execute(line.to_string()))
  }
  results
}

///|
/// Check if shell is still running
pub fn RuntimeShell::is_running(self : RuntimeShell) -> Bool {
  self.running
}

///|
/// Get the backend for direct access
pub fn RuntimeShell::get_backend(self : RuntimeShell) -> @runtime.MemfsBackend {
  self.backend
}

// Shell-specific builtins

///|
fn builtin_exit(_ctx : @runtime.ProcessContext) -> Int {
  0
}

///|
fn builtin_help(ctx : @runtime.ProcessContext) -> Int {
  let help =
    #|Available commands:
    #|  echo [args...]     - Print arguments
    #|  cat [file...]      - Display file contents
    #|  ls [dir]           - List directory
    #|  mkdir dir          - Create directory
    #|  rm file            - Remove file
    #|  touch file         - Create empty file
    #|  cp src dst         - Copy file
    #|  mv src dst         - Move/rename file
    #|  pwd                - Print working directory
    #|  cd [dir]           - Change directory
    #|  env                - Show environment
    #|  head [-n N] file   - Show first N lines
    #|  tail [-n N] file   - Show last N lines
    #|  grep pattern file  - Search for pattern
    #|  wc [file]          - Count lines/words/bytes
    #|  true               - Exit with 0
    #|  false              - Exit with 1
    #|  help               - Show this help
    #|  exit               - Exit shell
    #|
  ctx.write_stdout(help)
  0
}
