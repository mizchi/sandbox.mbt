/// Minimal shell implementation (busybox-like)

/// Shell instance
pub struct Shell {
  backend : MemfsBackend
  mut running : Bool
}

///|
pub fn Shell::new() -> Shell {
  let backend = MemfsBackend::new()
  backend.register_builtins()
  // Register shell-specific commands
  backend.register("exit", builtin_exit)
  backend.register("help", builtin_help)
  { backend, running: true }
}

///|
pub fn Shell::with_backend(backend : MemfsBackend) -> Shell {
  backend.register_builtins()
  backend.register("exit", builtin_exit)
  backend.register("help", builtin_help)
  { backend, running: true }
}

/// Execute a single command line
pub fn Shell::execute(self : Shell, line : String) -> ShellResult {
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
  let cmd = Command::new(program)
    .args(args)
    .stdout(Stdio::Piped)
    .stderr(Stdio::Piped)

  let result : Result[ShellResult, ProcessError] = try {
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

/// Execute multiple commands (script)
pub fn Shell::execute_script(self : Shell, script : String) -> Array[ShellResult] {
  let results : Array[ShellResult] = []
  for line in script.split("\n") {
    if not(self.running) {
      break
    }
    results.push(self.execute(line.to_string()))
  }
  results
}

/// Check if shell is still running
pub fn Shell::is_running(self : Shell) -> Bool {
  self.running
}

/// Get the backend for direct access
pub fn Shell::get_backend(self : Shell) -> MemfsBackend {
  self.backend
}

/// Shell execution result
pub struct ShellResult {
  exit_code : Int
  stdout : String
  stderr : String
}

///|
pub fn ShellResult::success(self : ShellResult) -> Bool {
  self.exit_code == 0
}

/// Parse command line into parts (simple tokenizer)
fn parse_command_line(line : String) -> Array[String] {
  let parts : Array[String] = []
  let current : Array[Char] = []
  let mut in_quote = false
  let mut quote_char : Char = ' '

  for c in line {
    if in_quote {
      if c == quote_char {
        in_quote = false
      } else {
        current.push(c)
      }
    } else if c == '"' || c == '\'' {
      in_quote = true
      quote_char = c
    } else if c == ' ' || c == '\t' {
      if current.length() > 0 {
        parts.push(String::from_array(current[:]))
        current.clear()
      }
    } else {
      current.push(c)
    }
  }

  if current.length() > 0 {
    parts.push(String::from_array(current[:]))
  }

  parts
}

// Shell-specific builtins

///|
fn builtin_exit(_ctx : ProcessContext) -> Int {
  0
}

///|
fn builtin_help(ctx : ProcessContext) -> Int {
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
