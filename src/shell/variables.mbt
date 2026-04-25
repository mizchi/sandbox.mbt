/// Shell variable expansion

///|
/// Variable environment for shell execution
pub struct VarEnv {
  /// User-defined variables
  vars : Map[String, String]
  /// Positional parameters ($0, $1, ...)
  args : Array[String]
  /// Last exit code
  mut last_exit : Int
  /// Git objects storage (hash -> object)
  git_objects : Map[String, GitObject]
  /// Git index (path -> entry)
  git_index : Map[String, IndexEntry]
  /// Command substitution handler
  mut command_sub_handler : ((String) -> String)?
}

///|
pub fn VarEnv::new() -> VarEnv {
  {
    vars: {},
    args: [],
    last_exit: 0,
    git_objects: {},
    git_index: {},
    command_sub_handler: None,
  }
}

///|
pub fn VarEnv::with_args(args : Array[String]) -> VarEnv {
  {
    vars: {},
    args,
    last_exit: 0,
    git_objects: {},
    git_index: {},
    command_sub_handler: None,
  }
}

///|
/// Set command substitution handler
pub fn VarEnv::set_command_sub_handler(
  self : VarEnv,
  handler : (String) -> String,
) -> Unit {
  self.command_sub_handler = Some(handler)
}

///|
/// Get command substitution handler
pub fn VarEnv::get_command_sub_handler(self : VarEnv) -> ((String) -> String)? {
  self.command_sub_handler
}

///|
/// Store a git object
pub fn VarEnv::store_git_object(
  self : VarEnv,
  hash : String,
  obj : GitObject,
) -> Unit {
  self.git_objects.set(hash, obj)
}

///|
/// Get git objects map
pub fn VarEnv::get_git_objects(self : VarEnv) -> Map[String, GitObject] {
  self.git_objects
}

///|
/// Get git index map
pub fn VarEnv::get_git_index(self : VarEnv) -> Map[String, IndexEntry] {
  self.git_index
}

///|
/// Get a variable value
pub fn VarEnv::get(self : VarEnv, name : String) -> String? {
  self.vars.get(name)
}

///|
/// Set a variable value
pub fn VarEnv::set(self : VarEnv, name : String, value : String) -> Unit {
  self.vars.set(name, value)
}

///|
/// Get the last exit code
pub fn VarEnv::get_last_exit(self : VarEnv) -> Int {
  self.last_exit
}

///|
/// Set the last exit code
pub fn VarEnv::set_last_exit(self : VarEnv, code : Int) -> Unit {
  self.last_exit = code
}

///|
/// Get a positional parameter
pub fn VarEnv::get_arg(self : VarEnv, n : Int) -> String? {
  if n >= 0 && n < self.args.length() {
    Some(self.args[n])
  } else {
    None
  }
}

///|
/// Expand a single Word to string
pub fn expand_word(
  word : Word,
  env : VarEnv,
  ctx : @posix.PosixContext,
) -> String {
  match word {
    Literal(s) => s
    Variable(name) =>
      // First check shell variables, then environment
      match env.get(name) {
        Some(v) => v
        None =>
          match ctx.getenv(name) {
            Some(v) => v
            None => ""
          }
      }
    Word::ExitCode => env.last_exit.to_string()
    ArgN(n) =>
      match env.get_arg(n) {
        Some(v) => v
        None => ""
      }
    ArgAll => {
      // $@ - all positional params as separate words (joined with space for string)
      let buf = StringBuilder::new()
      for i = 1; i < env.args.length(); i = i + 1 {
        if i > 1 {
          buf.write_char(' ')
        }
        buf.write_string(env.args[i])
      }
      buf.to_string()
    }
    ArgAllString => {
      // $* - all positional params as single string (joined with first char of IFS, default space)
      let buf = StringBuilder::new()
      for i = 1; i < env.args.length(); i = i + 1 {
        if i > 1 {
          buf.write_char(' ')
        }
        buf.write_string(env.args[i])
      }
      buf.to_string()
    }
    ArgCount => {
      // $# - number of positional params (excluding $0)
      let count = if env.args.length() > 0 { env.args.length() - 1 } else { 0 }
      count.to_string()
    }
    LastPid =>
      // $! - PID of last background command (not implemented, return 0)
      "0"
    ShellPid =>
      // $$ - PID of current shell (not implemented, return fixed value)
      "1"
    CommandSub(cmd) =>
      // $(cmd) - execute command and return its output
      // We need to parse and execute the command
      // This creates a circular dependency, so we use a callback stored in env
      match env.get_command_sub_handler() {
        Some(handler) => handler(cmd)
        None => "" // No handler available
      }
    Quoted(words) => {
      let buf = StringBuilder::new()
      for w in words {
        buf.write_string(expand_word(w, env, ctx))
      }
      buf.to_string()
    }
  }
}

///|
/// Expand an array of Words to strings (without glob expansion)
pub fn expand_words(
  words : Array[Word],
  env : VarEnv,
  ctx : @posix.PosixContext,
) -> Array[String] {
  let result : Array[String] = []
  for w in words {
    result.push(expand_word(w, env, ctx))
  }
  result
}

///|
/// Expand an array of Words to strings with glob expansion
pub fn expand_words_with_glob(
  words : Array[Word],
  env : VarEnv,
  ctx : @posix.PosixContext,
) -> Array[String] {
  let result : Array[String] = []
  let cwd = ctx.getcwd()
  for w in words {
    let expanded = expand_word(w, env, ctx)
    // Apply glob expansion if the word contains glob characters
    // and is not quoted (Literal words can contain glob chars)
    if has_glob_chars(expanded) && !(is_quoted_word(w)) {
      let glob_results = expand_glob(expanded, ctx.get_fs(), cwd)
      for path in glob_results {
        result.push(path)
      }
    } else {
      result.push(expanded)
    }
  }
  result
}

///|
/// Check if a word is quoted (should not be glob-expanded)
fn is_quoted_word(w : Word) -> Bool {
  match w {
    Quoted(_) => true
    _ => false
  }
}
