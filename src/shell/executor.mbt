/// Shell executor - executes AST

///|
/// Executor for shell AST
pub struct Executor {
  ctx : @posix.PosixContext
  env : VarEnv
  commands : Map[
    String,
    (@posix.PosixContext, Array[String], StringBuilder, StringBuilder) -> Int,
  ]
}

///|
pub fn Executor::new(ctx : @posix.PosixContext) -> Executor {
  let exec : Executor = { ctx, env: VarEnv::new(), commands: {} }
  exec.register_builtins()
  exec.setup_command_sub_handler()
  exec
}

///|
pub fn Executor::with_args(
  ctx : @posix.PosixContext,
  args : Array[String],
) -> Executor {
  let exec : Executor = { ctx, env: VarEnv::with_args(args), commands: {} }
  exec.register_builtins()
  exec.setup_command_sub_handler()
  exec
}

///|
/// Setup command substitution handler
fn Executor::setup_command_sub_handler(self : Executor) -> Unit {
  // Create a handler that parses and executes commands
  let ctx = self.ctx
  let env = self.env
  let commands = self.commands
  self.env.set_command_sub_handler(fn(cmd_str) {
    // Parse the command
    let ast = parse(cmd_str) catch { _ => return "" }
    // Create a temporary executor with shared state
    let temp_exec : Executor = { ctx, env, commands }
    // Execute and return stdout
    let result = temp_exec.execute(ast)
    // Strip trailing newline (shell convention)
    let output = result.stdout
    if output.length() > 0 && output.to_array()[output.length() - 1] == '\n' {
      substring_simple(output, 0, output.length() - 1)
    } else {
      output
    }
  })
}

///|
fn Executor::register_builtins(self : Executor) -> Unit {
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
  self.commands.set("test", exec_test_cmd)

  // Register git commands
  register_git_commands(self, fn(name, handler) {
    self.commands.set(name, handler)
  })
}

///|
/// Register a custom command
pub fn Executor::register(
  self : Executor,
  name : String,
  handler : (@posix.PosixContext, Array[String], StringBuilder, StringBuilder) -> Int,
) -> Unit {
  self.commands.set(name, handler)
}

///|
/// Get the variable environment
pub fn Executor::get_env(self : Executor) -> VarEnv {
  self.env
}

///|
/// Execute an AST node
pub fn Executor::execute(self : Executor, ast : Ast) -> ExecResult {
  match ast {
    Empty => { exit_code: 0, stdout: "", stderr: "" }
    SimpleCommand(words, redirects) => self.exec_simple(words, redirects)
    Pipeline(cmds) => self.exec_pipeline(cmds)
    AndList(left, right) => {
      let l_result = self.execute(left)
      if l_result.exit_code == 0 {
        let r_result = self.execute(right)
        {
          exit_code: r_result.exit_code,
          stdout: l_result.stdout + r_result.stdout,
          stderr: l_result.stderr + r_result.stderr,
        }
      } else {
        l_result
      }
    }
    OrList(left, right) => {
      let l_result = self.execute(left)
      if l_result.exit_code != 0 {
        let r_result = self.execute(right)
        {
          exit_code: r_result.exit_code,
          stdout: l_result.stdout + r_result.stdout,
          stderr: l_result.stderr + r_result.stderr,
        }
      } else {
        l_result
      }
    }
    Sequence(left, right) => {
      let l_result = self.execute(left)
      let r_result = self.execute(right)
      {
        exit_code: r_result.exit_code,
        stdout: l_result.stdout + r_result.stdout,
        stderr: l_result.stderr + r_result.stderr,
      }
    }
    IfStmt(cond, then_body, elif_list, else_body) =>
      self.exec_if(cond, then_body, elif_list, else_body)
    ForLoop(varname, items, body) => self.exec_for(varname, items, body)
    WhileLoop(cond, body, is_until) => self.exec_while(cond, body, is_until)
    CaseStmt(word, cases) => self.exec_case(word, cases)
    Assignment(name, value) => {
      let expanded = expand_word(value, self.env, self.ctx)
      self.env.set(name, expanded)
      { exit_code: 0, stdout: "", stderr: "" }
    }
    Subshell(body) =>
      // In a real shell, subshell would fork. Here we just execute in same context.
      self.execute(body)
    BraceGroup(body) =>
      // Brace group executes in current context
      self.execute(body)
    FuncDef(name, body) => {
      // Register function as a command
      let func_body = body
      self.commands.set(name, fn(ctx, args, stdout, stderr) {
        // Create a new executor for the function
        let func_exec = Executor::with_args(ctx, args)
        // Execute the body
        let result = func_exec.execute(func_body)
        stdout.write_string(result.stdout)
        stderr.write_string(result.stderr)
        result.exit_code
      })
      { exit_code: 0, stdout: "", stderr: "" }
    }
    Background(cmd) => {
      // In a real shell, this would fork and run in background.
      // Since we don't have real processes, we just execute synchronously
      // but return immediately with exit code 0.
      let result = self.execute(cmd)
      // In real shell, we'd return the background job's PID
      // For now, just execute and return success
      { exit_code: 0, stdout: result.stdout, stderr: result.stderr }
    }
  }
}

///|
fn Executor::exec_simple(
  self : Executor,
  words : Array[Word],
  redirects : Array[Redirect],
) -> ExecResult {
  if words.length() == 0 {
    return { exit_code: 0, stdout: "", stderr: "" }
  }

  // Expand words with glob expansion
  let expanded = expand_words_with_glob(words, self.env, self.ctx)
  if expanded.length() == 0 {
    return { exit_code: 0, stdout: "", stderr: "" }
  }
  let cmd = expanded[0]
  let args : Array[String] = []
  for i = 1; i < expanded.length(); i = i + 1 {
    args.push(expanded[i])
  }

  // Execute command
  let stdout = StringBuilder::new()
  let stderr = StringBuilder::new()
  let exit_code = match self.commands.get(cmd) {
    Some(handler) => handler(self.ctx, args, stdout, stderr)
    None => {
      stderr.write_string(cmd + ": command not found\n")
      127
    }
  }

  // Update last exit code
  self.env.set_last_exit(exit_code)

  // Handle redirects (write output to files)
  let stdout_str = stdout.to_string()
  let stderr_str = stderr.to_string()

  for redir in redirects {
    let target_path = expand_word(redir.target, self.env, self.ctx)
    let abs_path = self.ctx.resolve_path(target_path)
    match redir.kind {
      Out =>
        if redir.fd == 1 {
          self.ctx.get_fs().write_string(abs_path, stdout_str) catch {
            _ => ()
          }
        } else if redir.fd == 2 {
          self.ctx.get_fs().write_string(abs_path, stderr_str) catch {
            _ => ()
          }
        }
      Append => {
        let existing = self.ctx.get_fs().read_string(abs_path) catch { _ => "" }
        if redir.fd == 1 {
          self.ctx.get_fs().write_string(abs_path, existing + stdout_str) catch {
            _ => ()
          }
        }
      }
      In =>
        // Input redirect - would need to pass to command
        // For now, just ignore
        ()
      OutDup =>
        // Output dup: e.g., 2>&1 means redirect fd 2 to where fd 1 goes
        // For now, we simulate by copying the appropriate output
        ()
      InDup =>
        // Input dup: e.g., 0<&3 means read from fd 3
        // For now, just ignore
        ()
      RedirectKind::HereDoc =>
        // Here document - content is in target
        // In a real shell, this would be fed to stdin of the command
        // For now, just ignore (would need stdin support in commands)
        ()
      RedirectKind::HereDocStrip =>
        // Here document with tab stripping
        // Same as above for now
        ()
    }
  }

  // If output was redirected, don't return it
  let has_stdout_redir = redirects.iter().any(fn(r) { r.fd == 1 })
  let has_stderr_redir = redirects.iter().any(fn(r) { r.fd == 2 })

  {
    exit_code,
    stdout: if has_stdout_redir {
      ""
    } else {
      stdout_str
    },
    stderr: if has_stderr_redir {
      ""
    } else {
      stderr_str
    },
  }
}

///|
fn Executor::exec_pipeline(self : Executor, cmds : Array[Ast]) -> ExecResult {
  // Execute pipeline by passing stdout of each command to stdin of next
  // For simplicity, we just execute sequentially and collect all output
  let all_stdout = StringBuilder::new()
  let all_stderr = StringBuilder::new()
  let mut last_exit = 0

  // For proper pipeline, we'd need to implement stdin passing
  // For now, execute left-to-right and concatenate outputs
  let mut prev_output = ""
  for i, cmd in cmds {
    // Execute command
    let result = self.execute(cmd)

    // In a real pipeline, prev_output would be piped to stdin
    // For now, we just concatenate outputs
    if i == cmds.length() - 1 {
      all_stdout.write_string(result.stdout)
    }
    all_stderr.write_string(result.stderr)
    last_exit = result.exit_code
    prev_output = result.stdout
    ignore(prev_output)
  }

  self.env.set_last_exit(last_exit)
  {
    exit_code: last_exit,
    stdout: all_stdout.to_string(),
    stderr: all_stderr.to_string(),
  }
}

///|
fn Executor::exec_if(
  self : Executor,
  cond : Ast,
  then_body : Ast,
  elif_list : Array[(Ast, Ast)],
  else_body : Ast?,
) -> ExecResult {
  // Execute condition
  let cond_result = self.execute(cond)
  if cond_result.exit_code == 0 {
    let body_result = self.execute(then_body)
    return {
      exit_code: body_result.exit_code,
      stdout: cond_result.stdout + body_result.stdout,
      stderr: cond_result.stderr + body_result.stderr,
    }
  }

  // Check elif clauses
  let mut all_stdout = cond_result.stdout
  let mut all_stderr = cond_result.stderr
  for item in elif_list {
    let (elif_cond, elif_body) = item
    let elif_result = self.execute(elif_cond)
    all_stdout = all_stdout + elif_result.stdout
    all_stderr = all_stderr + elif_result.stderr
    if elif_result.exit_code == 0 {
      let body_result = self.execute(elif_body)
      return {
        exit_code: body_result.exit_code,
        stdout: all_stdout + body_result.stdout,
        stderr: all_stderr + body_result.stderr,
      }
    }
  }

  // Execute else if present
  match else_body {
    Some(body) => {
      let body_result = self.execute(body)
      {
        exit_code: body_result.exit_code,
        stdout: all_stdout + body_result.stdout,
        stderr: all_stderr + body_result.stderr,
      }
    }
    None => { exit_code: 0, stdout: all_stdout, stderr: all_stderr }
  }
}

///|
fn Executor::exec_for(
  self : Executor,
  varname : String,
  items : Array[Word],
  body : Ast,
) -> ExecResult {
  let all_stdout = StringBuilder::new()
  let all_stderr = StringBuilder::new()
  let mut last_exit = 0

  for item in items {
    let value = expand_word(item, self.env, self.ctx)
    self.env.set(varname, value)
    let result = self.execute(body)
    all_stdout.write_string(result.stdout)
    all_stderr.write_string(result.stderr)
    last_exit = result.exit_code
  }

  self.env.set_last_exit(last_exit)
  {
    exit_code: last_exit,
    stdout: all_stdout.to_string(),
    stderr: all_stderr.to_string(),
  }
}

///|
fn Executor::exec_while(
  self : Executor,
  cond : Ast,
  body : Ast,
  is_until : Bool,
) -> ExecResult {
  let all_stdout = StringBuilder::new()
  let all_stderr = StringBuilder::new()
  let mut last_exit = 0
  let mut iterations = 0
  let max_iterations = 1000 // Prevent infinite loops

  while iterations < max_iterations {
    let cond_result = self.execute(cond)
    all_stdout.write_string(cond_result.stdout)
    all_stderr.write_string(cond_result.stderr)

    let should_continue = if is_until {
      cond_result.exit_code != 0
    } else {
      cond_result.exit_code == 0
    }

    if !(should_continue) {
      break
    }

    let body_result = self.execute(body)
    all_stdout.write_string(body_result.stdout)
    all_stderr.write_string(body_result.stderr)
    last_exit = body_result.exit_code
    iterations += 1
  }

  self.env.set_last_exit(last_exit)
  {
    exit_code: last_exit,
    stdout: all_stdout.to_string(),
    stderr: all_stderr.to_string(),
  }
}

///|
fn Executor::exec_case(
  self : Executor,
  word : Word,
  cases : Array[CaseItem],
) -> ExecResult {
  let value = expand_word(word, self.env, self.ctx)

  for case_item in cases {
    for pattern in case_item.patterns {
      let pattern_str = expand_word(pattern, self.env, self.ctx)
      if match_pattern(value, pattern_str) {
        return self.execute(case_item.body)
      }
    }
  }

  { exit_code: 0, stdout: "", stderr: "" }
}

///|
/// Simple pattern matching (supports * as wildcard)
fn match_pattern(value : String, pattern : String) -> Bool {
  if pattern == "*" {
    return true
  }
  if pattern.has_prefix("*") && pattern.has_suffix("*") {
    let middle = pattern_substr(pattern, 1, pattern.length() - 1)
    return value.find(middle) is Some(_)
  }
  if pattern.has_prefix("*") {
    let suffix = pattern_substr(pattern, 1, pattern.length())
    return value.has_suffix(suffix)
  }
  if pattern.has_suffix("*") {
    let prefix = pattern_substr(pattern, 0, pattern.length() - 1)
    return value.has_prefix(prefix)
  }
  value == pattern
}

///|
fn pattern_substr(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new()
  for i = start; i < end && i < chars.length(); i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// Execute a shell script string
pub fn Executor::exec_script(self : Executor, script : String) -> ExecResult {
  let ast = parse(script) catch {
    ParseError(msg) =>
      return { exit_code: 2, stdout: "", stderr: "Parse error: " + msg + "\n" }
  }
  self.execute(ast)
}

// ============ Test command implementation ============

///|
fn exec_test_cmd(
  ctx : @posix.PosixContext,
  args : Array[String],
  _stdout : StringBuilder,
  _stderr : StringBuilder,
) -> Int {
  if args.length() == 0 {
    return 1 // false
  }

  // Single argument: true if non-empty string
  if args.length() == 1 {
    return if args[0].length() > 0 { 0 } else { 1 }
  }

  // Two arguments: unary operators
  if args.length() == 2 {
    return exec_test_unary(ctx, args[0], args[1])
  }

  // Three arguments: binary operators
  if args.length() == 3 {
    return exec_test_binary(args[0], args[1], args[2])
  }

  1
}

///|
fn exec_test_unary(
  ctx : @posix.PosixContext,
  op : String,
  operand : String,
) -> Int {
  match op {
    "-z" => if operand.length() == 0 { 0 } else { 1 }
    "-n" => if operand.length() > 0 { 0 } else { 1 }
    "-f" => {
      // Check if regular file (exists and not directory)
      let result : Int = try {
        let st = ctx.stat(operand)
        if st.is_dir() {
          1
        } else {
          0
        }
      } catch {
        _ => 1
      }
      result
    }
    "-d" => {
      // Check if directory
      let result : Int = try {
        let st = ctx.stat(operand)
        if st.is_dir() {
          0
        } else {
          1
        }
      } catch {
        _ => 1
      }
      result
    }
    "-e" => {
      // Check if exists
      let path = ctx.resolve_path(operand)
      if ctx.get_fs().exists(path) {
        0
      } else {
        1
      }
    }
    "!" => if operand == "0" || operand == "" { 0 } else { 1 }
    _ => 1
  }
}

///|
fn exec_test_binary(left : String, op : String, right : String) -> Int {
  match op {
    "=" | "==" => if left == right { 0 } else { 1 }
    "!=" => if left != right { 0 } else { 1 }
    "-eq" => {
      let l = parse_int_simple(left)
      let r = parse_int_simple(right)
      if l == r {
        0
      } else {
        1
      }
    }
    "-ne" => {
      let l = parse_int_simple(left)
      let r = parse_int_simple(right)
      if l != r {
        0
      } else {
        1
      }
    }
    "-lt" => {
      let l = parse_int_simple(left)
      let r = parse_int_simple(right)
      if l < r {
        0
      } else {
        1
      }
    }
    "-le" => {
      let l = parse_int_simple(left)
      let r = parse_int_simple(right)
      if l <= r {
        0
      } else {
        1
      }
    }
    "-gt" => {
      let l = parse_int_simple(left)
      let r = parse_int_simple(right)
      if l > r {
        0
      } else {
        1
      }
    }
    "-ge" => {
      let l = parse_int_simple(left)
      let r = parse_int_simple(right)
      if l >= r {
        0
      } else {
        1
      }
    }
    _ => 1
  }
}
