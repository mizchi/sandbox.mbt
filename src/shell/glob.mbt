/// Glob expansion for shell - uses @minimatch for pattern matching

///|
/// Re-export has_glob_chars from minimatch
pub fn has_glob_chars(s : String) -> Bool {
  @minimatch.has_glob_chars(s)
}

///|
/// Re-export glob_match from minimatch
pub fn glob_match(pattern : String, text : String) -> Bool {
  @minimatch.match_(pattern, text)
}

///|
/// Expand a glob pattern to matching file paths
/// Returns the expanded paths, or the original pattern if no matches
pub fn expand_glob(
  pattern : String,
  fs : &@fs.FileSystem,
  cwd : String,
) -> Array[String] {
  // If no glob chars, return as-is
  if !(@minimatch.has_glob_chars(pattern)) {
    return [pattern]
  }

  // Split pattern into directory and filename parts
  let (dir, file_pattern) = split_glob_path(pattern, cwd)

  // Get files in directory
  let entries = fs.readdir(dir) catch {
    _ => return [pattern] // Directory doesn't exist, return pattern as-is
  }

  // Match entries against pattern
  let matches : Array[String] = []
  for entry in entries {
    // Skip hidden files unless pattern starts with .
    if entry.has_prefix(".") && !(file_pattern.has_prefix(".")) {
      continue
    }
    if @minimatch.match_(file_pattern, entry) {
      let full_path = if dir == "/" {
        "/" + entry
      } else if dir.has_suffix("/") {
        dir + entry
      } else {
        dir + "/" + entry
      }
      matches.push(full_path)
    }
  }

  // Sort matches alphabetically
  matches.sort_by(fn(a, b) { a.compare(b) })

  // If no matches, return original pattern (bash behavior)
  if matches.is_empty() {
    [pattern]
  } else {
    matches
  }
}

///|
/// Split a glob pattern into directory and filename parts
fn split_glob_path(pattern : String, cwd : String) -> (String, String) {
  // Find last / before any glob chars
  let chars = pattern.to_array()
  let mut last_slash = -1
  let mut first_glob = chars.length()

  for i, c in chars {
    if c == '/' {
      last_slash = i
    }
    if (c == '*' || c == '?' || c == '[') && first_glob == chars.length() {
      first_glob = i
    }
  }

  // If glob appears before any slash, use cwd as directory
  if first_glob <= last_slash || last_slash == -1 {
    if pattern.has_prefix("/") {
      // Absolute path with glob
      let dir = glob_substr(pattern, 0, last_slash + 1)
      let file = glob_substr(pattern, last_slash + 1, pattern.length())
      (if dir.is_empty() { "/" } else { dir }, file)
    } else {
      // Relative path - use cwd
      (cwd, pattern)
    }
  } else {
    // Directory part is before the glob
    let dir = glob_substr(pattern, 0, last_slash)
    let file = glob_substr(pattern, last_slash + 1, pattern.length())
    // Make absolute if relative
    let abs_dir = if dir.has_prefix("/") {
      dir
    } else if cwd == "/" {
      "/" + dir
    } else {
      cwd + "/" + dir
    }
    (abs_dir, file)
  }
}

///|
fn glob_substr(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new()
  for i = start; i < end && i < chars.length(); i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// Expand multiple patterns, handling glob expansion
pub fn expand_globs(
  patterns : Array[String],
  fs : &@fs.FileSystem,
  cwd : String,
) -> Array[String] {
  let result : Array[String] = []
  for pattern in patterns {
    let expanded = expand_glob(pattern, fs, cwd)
    for path in expanded {
      result.push(path)
    }
  }
  result
}
