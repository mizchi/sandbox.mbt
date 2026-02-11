/// Simple shell interpreter for testing POSIX layer

///|
/// Command execution result
pub struct ExecResult {
  exit_code : Int
  stdout : String
  stderr : String
}

///|
/// Shell interpreter with bash-compatible features
/// Supports: &&, ||, |, ;, variables, if/for/while/case
pub struct Shell {
  ctx : @posix.PosixContext
  executor : Executor
  commands : Map[
    String,
    (@posix.PosixContext, Array[String], StringBuilder, StringBuilder) -> Int,
  ]
  mut last_exit_code : Int
}

///|
pub fn Shell::new(ctx : @posix.PosixContext) -> Shell {
  let executor = Executor::new(ctx)
  let shell : Shell = { ctx, executor, commands: {}, last_exit_code: 0 }
  // Register built-in commands (for backwards compatibility)
  shell.register_builtins()
  shell
}

///|
pub fn Shell::default() -> Shell {
  Shell::new(@posix.PosixContext::default())
}

///|
fn Shell::register_builtins(self : Shell) -> Unit {
  self.commands.set("echo", cmd_echo)
  self.commands.set("cat", cmd_cat)
  self.commands.set("ls", cmd_ls)
  self.commands.set("pwd", cmd_pwd)
  self.commands.set("cd", cmd_cd)
  self.commands.set("mkdir", cmd_mkdir)
  self.commands.set("touch", cmd_touch)
  self.commands.set("rm", cmd_rm)
  self.commands.set("true", cmd_true)
  self.commands.set("false", cmd_false)
  self.commands.set("exit", cmd_exit)
  self.commands.set("export", cmd_export)
  self.commands.set("env", cmd_env)
}

///|
/// Register a custom command
pub fn Shell::register(
  self : Shell,
  name : String,
  handler : (@posix.PosixContext, Array[String], StringBuilder, StringBuilder) -> Int,
) -> Unit {
  self.commands.set(name, handler)
  // Also register with executor for new parser
  self.executor.register(name, handler)
}

///|
/// Execute a single command line using new parser
pub fn Shell::exec_line(self : Shell, line : String) -> ExecResult {
  let trimmed = trim_string(line)
  if trimmed.length() == 0 || trimmed.has_prefix("#") {
    return { exit_code: 0, stdout: "", stderr: "" }
  }
  // Use new parser and executor
  let result = self.executor.exec_script(trimmed)
  self.last_exit_code = result.exit_code
  result
}

///|
/// Execute a script (multiple lines) using new parser
pub fn Shell::exec_script(self : Shell, script : String) -> ExecResult {
  // The new parser handles multi-line scripts natively
  let result = self.executor.exec_script(script)
  self.last_exit_code = result.exit_code
  result
}

///|
/// Get the context
pub fn Shell::get_ctx(self : Shell) -> @posix.PosixContext {
  self.ctx
}

// ============ Built-in Commands ============

///|
fn cmd_echo(
  _ctx : @posix.PosixContext,
  args : Array[String],
  stdout : StringBuilder,
  _stderr : StringBuilder,
) -> Int {
  stdout.write_string(args.join(" "))
  stdout.write_string("\n")
  0
}

///|
fn cmd_cat(
  ctx : @posix.PosixContext,
  args : Array[String],
  stdout : StringBuilder,
  stderr : StringBuilder,
) -> Int {
  if args.length() == 0 {
    return 0
  }
  for path in args {
    let abs_path = ctx.resolve_path(path)
    try {
      let content = ctx.get_fs().read_string(abs_path)
      stdout.write_string(content)
    } catch {
      _ => {
        stderr.write_string("cat: " + path + ": No such file or directory\n")
        return 1
      }
    }
  }
  0
}

///|
fn cmd_ls(
  ctx : @posix.PosixContext,
  args : Array[String],
  stdout : StringBuilder,
  stderr : StringBuilder,
) -> Int {
  // If no args, list current directory
  if args.length() == 0 {
    return ls_path(ctx, ".", stdout, stderr)
  }

  // Process each argument
  let mut exit_code = 0
  for arg in args {
    let code = ls_path(ctx, arg, stdout, stderr)
    if code != 0 {
      exit_code = code
    }
  }
  exit_code
}

///|
fn ls_path(
  ctx : @posix.PosixContext,
  path : String,
  stdout : StringBuilder,
  stderr : StringBuilder,
) -> Int {
  let abs_path = ctx.resolve_path(path)

  // Check if it's a file or directory
  if ctx.get_fs().is_file(abs_path) {
    // It's a file - just print its name
    let name = get_basename(path)
    stdout.write_string(name)
    stdout.write_string("\n")
    return 0
  }

  if ctx.get_fs().is_dir(abs_path) {
    // It's a directory - list its contents
    try {
      let entries = ctx.get_fs().readdir(abs_path)
      for entry in entries {
        stdout.write_string(entry)
        stdout.write_string("\n")
      }
      0
    } catch {
      _ => {
        stderr.write_string("ls: cannot access '" + path + "'\n")
        1
      }
    }
  } else {
    stderr.write_string(
      "ls: cannot access '" + path + "': No such file or directory\n",
    )
    1
  }
}

///|
fn get_basename(path : String) -> String {
  let chars = path.to_array()
  let mut last_slash = -1
  for i, c in chars {
    if c == '/' {
      last_slash = i
    }
  }
  if last_slash == -1 {
    path
  } else if last_slash == chars.length() - 1 {
    // Trailing slash - find previous slash
    let mut prev_slash = -1
    for i = 0; i < last_slash; i = i + 1 {
      if chars[i] == '/' {
        prev_slash = i
      }
    }
    let buf = StringBuilder::new()
    for i = prev_slash + 1; i < last_slash; i = i + 1 {
      buf.write_char(chars[i])
    }
    buf.to_string()
  } else {
    let buf = StringBuilder::new()
    for i = last_slash + 1; i < chars.length(); i = i + 1 {
      buf.write_char(chars[i])
    }
    buf.to_string()
  }
}

///|
fn cmd_pwd(
  ctx : @posix.PosixContext,
  _args : Array[String],
  stdout : StringBuilder,
  _stderr : StringBuilder,
) -> Int {
  stdout.write_string(ctx.getcwd())
  stdout.write_string("\n")
  0
}

///|
fn cmd_cd(
  ctx : @posix.PosixContext,
  args : Array[String],
  _stdout : StringBuilder,
  stderr : StringBuilder,
) -> Int {
  let path = if args.length() > 0 { args[0] } else { "~" }
  try {
    ctx.chdir(path)
    0
  } catch {
    _ => {
      stderr.write_string("cd: " + path + ": No such directory\n")
      1
    }
  }
}

///|
fn cmd_mkdir(
  ctx : @posix.PosixContext,
  args : Array[String],
  _stdout : StringBuilder,
  stderr : StringBuilder,
) -> Int {
  if args.length() == 0 {
    stderr.write_string("mkdir: missing operand\n")
    return 1
  }
  for path in args {
    let abs_path = ctx.resolve_path(path)
    ctx.get_fs().mkdir(abs_path) catch {
      _ => {
        stderr.write_string("mkdir: cannot create directory '" + path + "'\n")
        return 1
      }
    }
  }
  0
}

///|
fn cmd_touch(
  ctx : @posix.PosixContext,
  args : Array[String],
  _stdout : StringBuilder,
  stderr : StringBuilder,
) -> Int {
  if args.length() == 0 {
    stderr.write_string("touch: missing operand\n")
    return 1
  }
  for path in args {
    let abs_path = ctx.resolve_path(path)
    if not(ctx.get_fs().exists(abs_path)) {
      ctx.get_fs().write_string(abs_path, "") catch {
        _ => {
          stderr.write_string("touch: cannot touch '" + path + "'\n")
          return 1
        }
      }
    }
  }
  0
}

///|
fn cmd_rm(
  ctx : @posix.PosixContext,
  args : Array[String],
  _stdout : StringBuilder,
  stderr : StringBuilder,
) -> Int {
  if args.length() == 0 {
    stderr.write_string("rm: missing operand\n")
    return 1
  }
  for path in args {
    let abs_path = ctx.resolve_path(path)
    ctx.get_fs().remove(abs_path) catch {
      _ => {
        stderr.write_string("rm: cannot remove '" + path + "'\n")
        return 1
      }
    }
  }
  0
}

///|
fn cmd_true(
  _ctx : @posix.PosixContext,
  _args : Array[String],
  _stdout : StringBuilder,
  _stderr : StringBuilder,
) -> Int {
  0
}

///|
fn cmd_false(
  _ctx : @posix.PosixContext,
  _args : Array[String],
  _stdout : StringBuilder,
  _stderr : StringBuilder,
) -> Int {
  1
}

///|
fn cmd_exit(
  _ctx : @posix.PosixContext,
  args : Array[String],
  _stdout : StringBuilder,
  _stderr : StringBuilder,
) -> Int {
  if args.length() > 0 {
    parse_int_simple(args[0])
  } else {
    0
  }
}

///|
fn parse_int_simple(s : String) -> Int {
  let mut result = 0
  let mut negative = false
  let mut started = false
  for c in s {
    if c == '-' && not(started) {
      negative = true
      started = true
    } else if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
      started = true
    }
  }
  if negative {
    -result
  } else {
    result
  }
}

///|
fn cmd_export(
  ctx : @posix.PosixContext,
  args : Array[String],
  _stdout : StringBuilder,
  stderr : StringBuilder,
) -> Int {
  for arg in args {
    match arg.find("=") {
      Some(i) => {
        let name = substring_range(arg, 0, i)
        let value = substring_range(arg, i + 1, arg.length())
        ctx.setenv(name, value)
      }
      None => {
        stderr.write_string("export: invalid argument: " + arg + "\n")
        return 1
      }
    }
  }
  0
}

///|
fn cmd_env(
  ctx : @posix.PosixContext,
  _args : Array[String],
  stdout : StringBuilder,
  _stderr : StringBuilder,
) -> Int {
  // Print known environment variables
  let vars = ["HOME", "PATH", "USER", "SHELL", "PWD"]
  for name in vars {
    match ctx.getenv(name) {
      Some(value) => stdout.write_string(name + "=" + value + "\n")
      None => ()
    }
  }
  0
}

// ============ Helpers ============

///|
fn parse_command_line(line : String) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  let mut in_quote = false
  let mut quote_char : Char = '"'
  for c in line {
    if in_quote {
      if c == quote_char {
        in_quote = false
      } else {
        current.write_char(c)
      }
    } else if c == '"' || c == '\'' {
      in_quote = true
      quote_char = c
    } else if c == ' ' || c == '\t' {
      if current.to_string().length() > 0 {
        result.push(current.to_string())
        current.reset()
      }
    } else {
      current.write_char(c)
    }
  }
  if current.to_string().length() > 0 {
    result.push(current.to_string())
  }
  result
}

///|
fn trim_string(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  let mut end = chars.length()

  // Trim leading whitespace
  while start < end {
    let c = chars[start]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      start += 1
    } else {
      break
    }
  }

  // Trim trailing whitespace
  while end > start {
    let c = chars[end - 1]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      end -= 1
    } else {
      break
    }
  }
  substring_range(s, start, end)
}

///|
fn substring_range(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let result = StringBuilder::new()
  for i in start..<end {
    if i < chars.length() {
      result.write_char(chars[i])
    }
  }
  result.to_string()
}
