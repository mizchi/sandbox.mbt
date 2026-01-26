/// Builtin commands for MemfsBackend

///|
/// Register all builtin commands
pub fn MemfsBackend::register_builtins(self : MemfsBackend) -> Unit {
  self.register("echo", builtin_echo)
  self.register("cat", builtin_cat)
  self.register("ls", builtin_ls)
  self.register("mkdir", builtin_mkdir)
  self.register("rm", builtin_rm)
  self.register("pwd", builtin_pwd)
  self.register("cd", builtin_cd)
  self.register("env", builtin_env)
  self.register("true", builtin_true)
  self.register("false", builtin_false)
  self.register("head", builtin_head)
  self.register("tail", builtin_tail)
  self.register("wc", builtin_wc)
  self.register("grep", builtin_grep)
  self.register("touch", builtin_touch)
  self.register("cp", builtin_cp)
  self.register("mv", builtin_mv)
}

///|
fn builtin_echo(ctx : ProcessContext) -> Int {
  let output = ctx.args.join(" ")
  ctx.write_stdout(output + "\n")
  0
}

///|
fn builtin_cat(ctx : ProcessContext) -> Int {
  let backend = ctx.backend
  for path in ctx.args {
    let result : Result[Unit, IOError] = try {
      let fd = backend.open(path, OpenFlags::read_only())
      let data = backend.read(fd, 1024 * 1024) // 1MB max
      backend.close(fd)
      ctx.write_stdout(@utf8.decode_lossy(data[:]))
      Ok(())
    } catch {
      e => {
        ctx.write_stderr("cat: \{path}: \{e}\n")
        Err(e)
      }
    }
    if result is Err(_) {
      return 1
    }
  }
  0
}

///|
fn builtin_ls(ctx : ProcessContext) -> Int {
  let backend = ctx.backend
  let path = if ctx.args.is_empty() { backend.cwd() } else { ctx.args[0] }
  let result : Result[Unit, IOError] = try {
    let entries = backend.readdir(path)
    for entry in entries {
      let suffix = match entry.file_type {
        FileType::Directory => "/"
        _ => ""
      }
      ctx.write_stdout(entry.name + suffix + "\n")
    }
    Ok(())
  } catch {
    e => {
      ctx.write_stderr("ls: \{path}: \{e}\n")
      Err(e)
    }
  }
  if result is Err(_) {
    1
  } else {
    0
  }
}

///|
fn builtin_mkdir(ctx : ProcessContext) -> Int {
  let backend = ctx.backend
  if ctx.args.is_empty() {
    ctx.write_stderr("mkdir: missing operand\n")
    return 1
  }
  for path in ctx.args {
    let result : Result[Unit, IOError] = try {
      backend.mkdir(path)
      Ok(())
    } catch {
      e => {
        ctx.write_stderr("mkdir: \{path}: \{e}\n")
        Err(e)
      }
    }
    if result is Err(_) {
      return 1
    }
  }
  0
}

///|
fn builtin_rm(ctx : ProcessContext) -> Int {
  let backend = ctx.backend
  if ctx.args.is_empty() {
    ctx.write_stderr("rm: missing operand\n")
    return 1
  }
  for path in ctx.args {
    let result : Result[Unit, IOError] = try {
      backend.unlink(path)
      Ok(())
    } catch {
      e => {
        ctx.write_stderr("rm: \{path}: \{e}\n")
        Err(e)
      }
    }
    if result is Err(_) {
      return 1
    }
  }
  0
}

///|
fn builtin_pwd(ctx : ProcessContext) -> Int {
  ctx.write_stdout(ctx.backend.cwd() + "\n")
  0
}

///|
fn builtin_cd(ctx : ProcessContext) -> Int {
  let backend = ctx.backend
  let path = if ctx.args.is_empty() {
    backend.get_env("HOME").unwrap_or("/")
  } else {
    ctx.args[0]
  }
  let result : Result[Unit, IOError] = try {
    backend.chdir(path)
    Ok(())
  } catch {
    e => {
      ctx.write_stderr("cd: \{path}: \{e}\n")
      Err(e)
    }
  }
  if result is Err(_) {
    1
  } else {
    0
  }
}

///|
fn builtin_env(ctx : ProcessContext) -> Int {
  let backend = ctx.backend
  for k, v in backend.env_vars() {
    ctx.write_stdout("\{k}=\{v}\n")
  }
  0
}

///|
fn builtin_true(_ctx : ProcessContext) -> Int {
  0
}

///|
fn builtin_false(_ctx : ProcessContext) -> Int {
  1
}

///|
fn builtin_head(ctx : ProcessContext) -> Int {
  let mut n = 10
  let files : Array[String] = []

  // Parse args: head [-n NUM] [FILE...]
  let mut i = 0
  while i < ctx.args.length() {
    if ctx.args[i] == "-n" && i + 1 < ctx.args.length() {
      n = parse_int(ctx.args[i + 1]).unwrap_or(10)
      i += 2
    } else {
      files.push(ctx.args[i])
      i += 1
    }
  }
  let backend = ctx.backend
  fn output_head(content : String, n : Int, ctx : ProcessContext) -> Unit {
    let lines : Array[String] = content
      .split("\n")
      .map(fn(s) { s.to_string() })
      .collect()
    for j = 0; j < n && j < lines.length(); j = j + 1 {
      ctx.write_stdout(lines[j])
      if j < n - 1 && j < lines.length() - 1 {
        ctx.write_stdout("\n")
      }
    }
  }

  // If no files, read from stdin
  if files.is_empty() {
    output_head(ctx.read_stdin(), n, ctx)
    return 0
  }
  for path in files {
    let result : Result[Unit, IOError] = try {
      let fd = backend.open(path, OpenFlags::read_only())
      let data = backend.read(fd, 1024 * 1024)
      backend.close(fd)
      output_head(@utf8.decode_lossy(data[:]), n, ctx)
      Ok(())
    } catch {
      e => {
        ctx.write_stderr("head: \{path}: \{e}\n")
        Err(e)
      }
    }
    if result is Err(_) {
      return 1
    }
  }
  0
}

///|
fn builtin_tail(ctx : ProcessContext) -> Int {
  let mut n = 10
  let files : Array[String] = []

  // Parse args: tail [-n NUM] [FILE...]
  let mut i = 0
  while i < ctx.args.length() {
    if ctx.args[i] == "-n" && i + 1 < ctx.args.length() {
      n = parse_int(ctx.args[i + 1]).unwrap_or(10)
      i += 2
    } else {
      files.push(ctx.args[i])
      i += 1
    }
  }
  let backend = ctx.backend
  fn output_tail(content : String, n : Int, ctx : ProcessContext) -> Unit {
    let lines : Array[String] = content
      .split("\n")
      .map(fn(s) { s.to_string() })
      .collect()
    let start = if lines.length() > n { lines.length() - n } else { 0 }
    for j = start; j < lines.length(); j = j + 1 {
      ctx.write_stdout(lines[j])
      if j < lines.length() - 1 {
        ctx.write_stdout("\n")
      }
    }
  }

  if files.is_empty() {
    output_tail(ctx.read_stdin(), n, ctx)
    return 0
  }
  for path in files {
    let result : Result[Unit, IOError] = try {
      let fd = backend.open(path, OpenFlags::read_only())
      let data = backend.read(fd, 1024 * 1024)
      backend.close(fd)
      output_tail(@utf8.decode_lossy(data[:]), n, ctx)
      Ok(())
    } catch {
      e => {
        ctx.write_stderr("tail: \{path}: \{e}\n")
        Err(e)
      }
    }
    if result is Err(_) {
      return 1
    }
  }
  0
}

///|
fn builtin_wc(ctx : ProcessContext) -> Int {
  let backend = ctx.backend
  fn count_stats(content : String) -> (Int, Int, Int) {
    let lines = content.split("\n").count()
    let words = content.split(" ").filter(fn(s) { not(s.is_empty()) }).count()
    let bytes = @utf8.encode(content[:]).length()
    (lines, words, bytes)
  }

  if ctx.args.is_empty() {
    let input = ctx.read_stdin()
    let (lines, words, bytes) = count_stats(input)
    ctx.write_stdout("\{lines}\t\{words}\t\{bytes}\n")
    return 0
  }
  for path in ctx.args {
    let result : Result[Unit, IOError] = try {
      let fd = backend.open(path, OpenFlags::read_only())
      let data = backend.read(fd, 1024 * 1024)
      backend.close(fd)
      let content = @utf8.decode_lossy(data[:])
      let (lines, words, bytes) = count_stats(content)
      ctx.write_stdout("\{lines}\t\{words}\t\{bytes}\t\{path}\n")
      Ok(())
    } catch {
      e => {
        ctx.write_stderr("wc: \{path}: \{e}\n")
        Err(e)
      }
    }
    if result is Err(_) {
      return 1
    }
  }
  0
}

///|
fn builtin_grep(ctx : ProcessContext) -> Int {
  if ctx.args.is_empty() {
    ctx.write_stderr("grep: missing pattern\n")
    return 1
  }
  let pattern = ctx.args[0]
  let files = ctx.args[1:]
  let backend = ctx.backend
  let mut found = false
  fn grep_content(
    content : String,
    pattern : String,
    ctx : ProcessContext,
  ) -> Bool {
    let mut matched = false
    for line in content.split("\n") {
      if line.to_string().contains(pattern) {
        ctx.write_stdout(line.to_string() + "\n")
        matched = true
      }
    }
    matched
  }

  if files.is_empty() {
    let input = ctx.read_stdin()
    if grep_content(input, pattern, ctx) {
      found = true
    }
  } else {
    for path in files {
      let result : Result[Unit, IOError] = try {
        let fd = backend.open(path, OpenFlags::read_only())
        let data = backend.read(fd, 1024 * 1024)
        backend.close(fd)
        let content = @utf8.decode_lossy(data[:])
        if grep_content(content, pattern, ctx) {
          found = true
        }
        Ok(())
      } catch {
        e => {
          ctx.write_stderr("grep: \{path}: \{e}\n")
          Err(e)
        }
      }
      if result is Err(_) {
        return 1
      }
    }
  }
  if found {
    0
  } else {
    1
  }
}

///|
fn builtin_touch(ctx : ProcessContext) -> Int {
  let backend = ctx.backend
  if ctx.args.is_empty() {
    ctx.write_stderr("touch: missing operand\n")
    return 1
  }
  for path in ctx.args {
    let result : Result[Unit, IOError] = try {
      let fd = backend.open(path, OpenFlags::create())
      backend.close(fd)
      Ok(())
    } catch {
      e => {
        ctx.write_stderr("touch: \{path}: \{e}\n")
        Err(e)
      }
    }
    if result is Err(_) {
      return 1
    }
  }
  0
}

///|
fn builtin_cp(ctx : ProcessContext) -> Int {
  let backend = ctx.backend
  if ctx.args.length() < 2 {
    ctx.write_stderr("cp: missing operand\n")
    return 1
  }
  let src = ctx.args[0]
  let dst = ctx.args[1]
  let result : Result[Unit, IOError] = try {
    let fd_src = backend.open(src, OpenFlags::read_only())
    let data = backend.read(fd_src, 1024 * 1024)
    backend.close(fd_src)
    let fd_dst = backend.open(dst, OpenFlags::create())
    let _ = backend.write(fd_dst, data)
    backend.close(fd_dst)
    Ok(())
  } catch {
    e => {
      ctx.write_stderr("cp: \{e}\n")
      Err(e)
    }
  }
  if result is Err(_) {
    1
  } else {
    0
  }
}

///|
fn builtin_mv(ctx : ProcessContext) -> Int {
  let backend = ctx.backend
  if ctx.args.length() < 2 {
    ctx.write_stderr("mv: missing operand\n")
    return 1
  }
  let src = ctx.args[0]
  let dst = ctx.args[1]
  let result : Result[Unit, IOError] = try {
    backend.rename(src, dst)
    Ok(())
  } catch {
    e => {
      ctx.write_stderr("mv: \{e}\n")
      Err(e)
    }
  }
  if result is Err(_) {
    1
  } else {
    0
  }
}

///|
fn parse_int(s : String) -> Int? {
  let mut result = 0
  for c in s {
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
  }
  Some(result)
}
