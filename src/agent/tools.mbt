/// Tool definitions and execution for coding agent

///|
/// Built-in tools for the coding agent
pub fn get_builtin_tools() -> Array[ToolDef] {
  let bash_schema =
    #|{"type":"object","properties":{"command":{"type":"string","description":"The bash command to execute"}},"required":["command"]}
  let read_schema =
    #|{"type":"object","properties":{"path":{"type":"string","description":"The file path to read"}},"required":["path"]}
  let write_schema =
    #|{"type":"object","properties":{"path":{"type":"string","description":"The file path to write"},"content":{"type":"string","description":"The content to write"}},"required":["path","content"]}
  let list_schema =
    #|{"type":"object","properties":{"path":{"type":"string","description":"The directory path to list (default: current directory)"}},"required":[]}
  [
    ToolDef::new(
      "bash", "Execute a bash command in the shell. Use this for running commands, git operations, etc.",
      bash_schema,
    ),
    ToolDef::new(
      "read_file", "Read the contents of a file at the specified path.", read_schema,
    ),
    ToolDef::new(
      "write_file", "Write content to a file at the specified path. Creates the file if it doesn't exist.",
      write_schema,
    ),
    ToolDef::new(
      "list_files", "List files and directories at the specified path.", list_schema,
    ),
  ]
}

///|
/// Tool executor that uses the shell environment
pub(all) struct ToolExecutor {
  shell : @shell.Shell
  ctx : @posix.PosixContext
}

///|
/// Create a new tool executor
pub fn ToolExecutor::new(
  shell : @shell.Shell,
  ctx : @posix.PosixContext,
) -> ToolExecutor {
  { shell, ctx }
}

///|
/// Execute a tool call
pub fn ToolExecutor::execute(
  self : ToolExecutor,
  call : ToolCall,
) -> ToolResult {
  match call.name {
    "bash" => self.execute_bash(call.arguments)
    "read_file" => self.execute_read_file(call.arguments)
    "write_file" => self.execute_write_file(call.arguments)
    "list_files" => self.execute_list_files(call.arguments)
    _ => ToolResult::err("Unknown tool: " + call.name)
  }
}

///|
/// Execute bash command
fn ToolExecutor::execute_bash(self : ToolExecutor, args : String) -> ToolResult {
  match parse_json_string(args, "command") {
    None => ToolResult::err("Missing 'command' argument")
    Some(command) => {
      let result = self.shell.exec_line(command)
      let output = StringBuilder::new()
      if not(result.stdout.is_empty()) {
        output.write_string(result.stdout)
      }
      if not(result.stderr.is_empty()) {
        if output.to_string().length() > 0 {
          output.write_string("\n")
        }
        output.write_string("[stderr] ")
        output.write_string(result.stderr)
      }
      if result.exit_code == 0 {
        ToolResult::ok(output.to_string())
      } else {
        ToolResult::{
          success: false,
          output: output.to_string(),
          error: Some("Exit code: " + result.exit_code.to_string()),
        }
      }
    }
  }
}

///|
/// Execute read_file
fn ToolExecutor::execute_read_file(
  self : ToolExecutor,
  args : String,
) -> ToolResult {
  match parse_json_string(args, "path") {
    None => ToolResult::err("Missing 'path' argument")
    Some(path) => {
      let result = self.shell.exec_line("cat " + escape_shell_arg(path))
      if result.exit_code == 0 {
        ToolResult::ok(result.stdout)
      } else {
        ToolResult::err(result.stderr)
      }
    }
  }
}

///|
/// Execute write_file
fn ToolExecutor::execute_write_file(
  self : ToolExecutor,
  args : String,
) -> ToolResult {
  let path = parse_json_string(args, "path")
  let content = parse_json_string(args, "content")
  match (path, content) {
    (Some(p), Some(c)) => {
      // Write directly to filesystem
      let abs_path = self.ctx.resolve_path(p)
      try {
        self.ctx.get_fs().write_string(abs_path, c)
        ToolResult::ok("File written: " + p)
      } catch {
        e => ToolResult::err("Failed to write file: " + e.to_string())
      }
    }
    _ => ToolResult::err("Missing 'path' or 'content' argument")
  }
}

///|
/// Execute list_files
fn ToolExecutor::execute_list_files(
  self : ToolExecutor,
  args : String,
) -> ToolResult {
  let path = parse_json_string(args, "path").unwrap_or("/")
  let result = self.shell.exec_line("ls " + escape_shell_arg(path))
  if result.exit_code == 0 {
    ToolResult::ok(result.stdout)
  } else {
    ToolResult::err(result.stderr)
  }
}

///|
/// Simple JSON string parser (extracts a string value by key)
fn parse_json_string(json : String, key : String) -> String? {
  // Simple pattern: "key":"value" or "key": "value"
  let pattern = "\"" + key + "\""
  let start = find_substring(json, pattern)
  guard start >= 0 else { return None }

  // Find the colon after the key
  let after_key = start + pattern.length()
  let mut colon_pos = after_key
  while colon_pos < json.length() && char_at(json, colon_pos) != ':' {
    colon_pos = colon_pos + 1
  }
  guard colon_pos < json.length() else { return None }

  // Skip whitespace and find opening quote
  let mut quote_start = colon_pos + 1
  while quote_start < json.length() &&
        (
          char_at(json, quote_start) == ' ' ||
          char_at(json, quote_start) == '\t'
        ) {
    quote_start = quote_start + 1
  }
  guard quote_start < json.length() && char_at(json, quote_start) == '"' else {
    return None
  }

  // Find closing quote (handle escapes)
  let mut quote_end = quote_start + 1
  let mut escaped = false
  while quote_end < json.length() {
    let c = char_at(json, quote_end)
    if escaped {
      escaped = false
    } else if c == '\\' {
      escaped = true
    } else if c == '"' {
      break
    }
    quote_end = quote_end + 1
  }
  guard quote_end < json.length() else { return None }

  // Extract and unescape the value
  let value = json[quote_start + 1:quote_end].to_string() catch {
    _ => return None
  }
  Some(unescape_json_string(value))
}

///|
/// Get character at index
fn char_at(s : String, i : Int) -> Char {
  s[i].unsafe_to_char()
}

///|
/// Find substring and return start index, or -1 if not found
fn find_substring(haystack : String, needle : String) -> Int {
  match haystack.find(needle[:]) {
    Some(i) => i
    None => -1
  }
}

///|
/// Unescape JSON string
fn unescape_json_string(s : String) -> String {
  let result = StringBuilder::new()
  let mut i = 0
  while i < s.length() {
    let c = char_at(s, i)
    if c == '\\' && i + 1 < s.length() {
      let next = char_at(s, i + 1)
      match next {
        'n' => result.write_char('\n')
        't' => result.write_char('\t')
        'r' => result.write_char('\r')
        '"' => result.write_char('"')
        '\\' => result.write_char('\\')
        _ => {
          result.write_char('\\')
          result.write_char(next)
        }
      }
      i = i + 2
    } else {
      result.write_char(c)
      i = i + 1
    }
  }
  result.to_string()
}

///|
/// Escape a string for shell argument
fn escape_shell_arg(s : String) -> String {
  "'" + s.replace(old="'", new="'\\''") + "'"
}
