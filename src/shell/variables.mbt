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
}

///|
pub fn VarEnv::new() -> VarEnv {
  { vars: {}, args: [], last_exit: 0, git_objects: {}, git_index: {} }
}

///|
pub fn VarEnv::with_args(args : Array[String]) -> VarEnv {
  { vars: {}, args, last_exit: 0, git_objects: {}, git_index: {} }
}

///|
/// Store a git object
pub fn VarEnv::store_git_object(self : VarEnv, hash : String, obj : GitObject) -> Unit {
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
pub fn expand_word(word : Word, env : VarEnv, ctx : @posix.PosixContext) -> String {
  match word {
    Literal(s) => s
    Variable(name) => {
      // First check shell variables, then environment
      match env.get(name) {
        Some(v) => v
        None => {
          match ctx.getenv(name) {
            Some(v) => v
            None => ""
          }
        }
      }
    }
    Word::ExitCode => env.last_exit.to_string()
    ArgN(n) => {
      match env.get_arg(n) {
        Some(v) => v
        None => ""
      }
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
    if has_glob_chars(expanded) && not(is_quoted_word(w)) {
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
