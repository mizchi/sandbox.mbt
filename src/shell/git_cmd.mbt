///| Git commands for shell

///|
/// Register git commands
pub fn register_git_commands(
  exec : Executor,
  register : (
    String,
    (@posix.PosixContext, Array[String], StringBuilder, StringBuilder) -> Int,
  ) -> Unit,
) -> Unit {
  register("git", fn(ctx, args, stdout, stderr) {
    cmd_git(ctx, args, stdout, stderr, exec)
  })
}

///|
/// Main git command dispatcher
fn cmd_git(
  ctx : @posix.PosixContext,
  args : Array[String],
  stdout : StringBuilder,
  stderr : StringBuilder,
  exec : Executor,
) -> Int {
  if args.length() == 0 {
    stderr.write_string("usage: git <command> [<args>]\n")
    stderr.write_string("\nCommands:\n")
    stderr.write_string("  init           Initialize repository\n")
    stderr.write_string("  add            Add file to index\n")
    stderr.write_string("  commit         Record changes to repository\n")
    stderr.write_string("  log            Show commit log\n")
    stderr.write_string("\nPlumbing commands:\n")
    stderr.write_string("  hash-object    Compute object ID\n")
    stderr.write_string("  cat-file       Show object content\n")
    stderr.write_string("  write-tree     Write index to tree\n")
    stderr.write_string("  commit-tree    Create commit from tree\n")
    return 1
  }

  let subcmd = args[0]
  let subargs : Array[String] = []
  for i = 1; i < args.length(); i = i + 1 {
    subargs.push(args[i])
  }

  match subcmd {
    "hash-object" => git_hash_object(ctx, subargs, stdout, stderr)
    "cat-file" => git_cat_file(ctx, subargs, stdout, stderr, exec)
    "init" => git_init(ctx, subargs, stdout, stderr, exec)
    "add" => git_add(ctx, subargs, stdout, stderr, exec)
    "commit" => git_commit(ctx, subargs, stdout, stderr, exec)
    "write-tree" => git_write_tree(ctx, subargs, stdout, stderr, exec)
    "commit-tree" => git_commit_tree(ctx, subargs, stdout, stderr, exec)
    "log" => git_log(ctx, subargs, stdout, stderr, exec)
    _ => {
      stderr.write_string("git: '\{subcmd}' is not a git command\n")
      1
    }
  }
}

///|
/// git hash-object [-w] [--stdin] <file>
fn git_hash_object(
  ctx : @posix.PosixContext,
  args : Array[String],
  stdout : StringBuilder,
  stderr : StringBuilder,
) -> Int {
  let mut write_object = false
  let mut use_stdin = false
  let mut file_path = ""

  for arg in args {
    if arg == "-w" {
      write_object = true
    } else if arg == "--stdin" {
      use_stdin = true
    } else if !(arg.has_prefix("-")) {
      file_path = arg
    }
  }

  // Get content
  let content : Bytes = if use_stdin {
    // For now, stdin not supported - return empty
    stderr.write_string("git hash-object: --stdin not supported yet\n")
    return 1
  } else if file_path.length() > 0 {
    let abs_path = ctx.resolve_path(file_path)
    let data = ctx.get_fs().read_file(abs_path) catch {
        e => {
          stderr.write_string("fatal: Cannot open '\{file_path}': \{e}\n")
          return 128
        }
      }
    data
  } else {
    stderr.write_string("usage: git hash-object [-w] [--stdin] <file>\n")
    return 1
  }

  // Compute hash
  let id = @git.hash_blob(content)
  stdout.write_string(id.to_hex())
  stdout.write_string("\n")

  // Write object if -w
  if write_object {
    let git_dir = ctx.resolve_path(".git")
    if !(ctx.get_fs().exists(git_dir)) {
      stderr.write_string("fatal: not a git repository\n")
      return 128
    }

    // Create object directory
    let hex = id.to_hex()
    let obj_dir = git_dir + "/objects/" + hex_substr(hex, 0, 2)
    ctx.get_fs().mkdir_p(obj_dir) catch {
      _ => ()
    }

    // Write compressed object
    let (_, compressed) = @git.create_blob(content)
    let obj_path = obj_dir + "/" + hex_substr(hex, 2, 38)
    ctx.get_fs().write_file(obj_path, compressed) catch {
      _ => ()
    }
  }

  0
}

///|
fn hex_substr(s : String, start : Int, len : Int) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new()
  for i = start; i < start + len && i < chars.length(); i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// git cat-file <type> <object>
/// git cat-file -p <object>
/// git cat-file -t <object>
fn git_cat_file(
  _ctx : @posix.PosixContext,
  args : Array[String],
  stdout : StringBuilder,
  stderr : StringBuilder,
  exec : Executor,
) -> Int {
  if args.length() < 2 {
    stderr.write_string("usage: git cat-file <type> <object>\n")
    stderr.write_string("       git cat-file -p <object>\n")
    return 1
  }

  let flag = args[0]
  let object_ref = args[1]

  // Look up object from stored objects
  let objects = exec.get_env().get_git_objects()

  match objects.get(object_ref) {
    Some(obj) => {
      match flag {
        "-t" => {
          stdout.write_string(obj.obj_type)
          stdout.write_string("\n")
        }
        "-s" => {
          stdout.write_string(obj.size.to_string())
          stdout.write_string("\n")
        }
        "-p" | "blob" | "tree" | "commit" => stdout.write_string(obj.content)
        _ => {
          stderr.write_string("git cat-file: unknown option '\{flag}'\n")
          return 1
        }
      }
      0
    }
    None => {
      stderr.write_string("fatal: Not a valid object name \{object_ref}\n")
      128
    }
  }
}

///|
/// git init
fn git_init(
  ctx : @posix.PosixContext,
  _args : Array[String],
  stdout : StringBuilder,
  _stderr : StringBuilder,
  _exec : Executor,
) -> Int {
  let git_dir = ctx.resolve_path(".git")

  // Create .git directory structure
  ctx.get_fs().mkdir_p(git_dir) catch {
    _ => ()
  }
  ctx.get_fs().mkdir_p(git_dir + "/objects") catch {
    _ => ()
  }
  ctx.get_fs().mkdir_p(git_dir + "/refs/heads") catch {
    _ => ()
  }

  // Create HEAD
  ctx.get_fs().write_string(git_dir + "/HEAD", "ref: refs/heads/main\n") catch {
    _ => ()
  }

  stdout.write_string("Initialized empty Git repository in \{git_dir}/\n")
  0
}

///|
/// git add <file>...
fn git_add(
  ctx : @posix.PosixContext,
  args : Array[String],
  _stdout : StringBuilder,
  stderr : StringBuilder,
  exec : Executor,
) -> Int {
  if args.length() == 0 {
    stderr.write_string("usage: git add <file>...\n")
    return 1
  }

  let git_dir = ctx.resolve_path(".git")
  if !(ctx.get_fs().exists(git_dir)) {
    stderr.write_string("fatal: not a git repository\n")
    return 128
  }

  let index = exec.get_env().get_git_index()

  for file_path in args {
    let abs_path = ctx.resolve_path(file_path)
    let content = ctx.get_fs().read_file(abs_path) catch {
        e => {
          stderr.write_string(
            "fatal: pathspec '\{file_path}' did not match any files: \{e}\n",
          )
          return 128
        }
      }

    // Compute blob hash
    let id = @git.hash_blob(content)

    // Store object in memory
    let (_, compressed) = @git.create_blob(content)
    let hex = id.to_hex()
    exec
    .get_env()
    .store_git_object(hex, GitObject::{
      obj_type: "blob",
      size: content.length(),
      content: bytes_to_string(content),
      compressed,
    })

    // Add to index
    index.set(file_path, IndexEntry::{
      mode: "100644",
      hash: hex,
      path: file_path,
    })
  }

  0
}

///|
/// git commit [-m <message>]
fn git_commit(
  ctx : @posix.PosixContext,
  args : Array[String],
  stdout : StringBuilder,
  stderr : StringBuilder,
  exec : Executor,
) -> Int {
  let git_dir = ctx.resolve_path(".git")
  if !(ctx.get_fs().exists(git_dir)) {
    stderr.write_string("fatal: not a git repository\n")
    return 128
  }

  // Parse -m message
  let mut message = ""
  let mut i = 0
  while i < args.length() {
    if args[i] == "-m" && i + 1 < args.length() {
      message = args[i + 1]
      i += 2
    } else {
      i += 1
    }
  }

  if message.length() == 0 {
    stderr.write_string("error: commit message required (-m)\n")
    return 1
  }

  let index = exec.get_env().get_git_index()

  if index.length() == 0 {
    stderr.write_string(
      "nothing to commit (create/copy files and use \"git add\" to track)\n",
    )
    return 1
  }

  // 1. Write tree from index
  let entries : Array[@git.TreeEntry] = []
  for path, entry in index {
    let id = @git.ObjectId::from_hex(entry.hash) catch {
      _ => @git.ObjectId::zero()
    }
    entries.push(@git.TreeEntry::new(entry.mode, path, id))
  }
  let (tree_id, tree_compressed) = @git.create_tree(entries)
  let tree_hex = tree_id.to_hex()

  // Store tree object
  exec
  .get_env()
  .store_git_object(tree_hex, GitObject::{
    obj_type: "tree",
    size: 0,
    content: "",
    compressed: tree_compressed,
  })

  // 2. Get parent commit from HEAD
  let head_ref = ctx.get_fs().read_string(git_dir + "/HEAD") catch {
      _ => "ref: refs/heads/main\n"
    }
  let parent_hash : String? = if head_ref.has_prefix("ref: ") {
    let ref_path = git_dir +
      "/" +
      trim_newline(hex_substr(head_ref, 5, head_ref.length() - 5))
    let hash = ctx.get_fs().read_string(ref_path) catch { _ => "" }
    let trimmed = trim_newline(hash)
    if trimmed.length() == 40 {
      Some(trimmed)
    } else {
      None
    }
  } else {
    let trimmed = trim_newline(head_ref)
    if trimmed.length() == 40 {
      Some(trimmed)
    } else {
      None
    }
  }

  // 3. Create commit
  let parents : Array[@git.ObjectId] = match parent_hash {
    Some(h) => {
      let id = @git.ObjectId::from_hex(h) catch { _ => @git.ObjectId::zero() }
      [id]
    }
    None => []
  }

  let author = exec.get_env().get("GIT_AUTHOR_NAME").unwrap_or("User") +
    " <" +
    exec.get_env().get("GIT_AUTHOR_EMAIL").unwrap_or("user@example.com") +
    ">"

  let timestamp = 1700000000L // TODO: get real timestamp

  let commit = @git.Commit::new(
    tree_id,
    parents,
    author,
    timestamp,
    "+0000",
    author,
    timestamp,
    "+0000",
    message + "\n",
  )

  let (commit_id, commit_compressed) = @git.create_commit(commit)
  let commit_hex = commit_id.to_hex()

  // Store commit object
  exec
  .get_env()
  .store_git_object(commit_hex, GitObject::{
    obj_type: "commit",
    size: 0,
    content: "",
    compressed: commit_compressed,
  })

  // 4. Update HEAD ref
  if head_ref.has_prefix("ref: ") {
    let ref_path = git_dir +
      "/" +
      trim_newline(hex_substr(head_ref, 5, head_ref.length() - 5))
    // Ensure parent directory exists
    let refs_dir = git_dir + "/refs/heads"
    ctx.get_fs().mkdir_p(refs_dir) catch {
      _ => ()
    }
    ctx.get_fs().write_string(ref_path, commit_hex + "\n") catch {
      _ => ()
    }
  }

  // 5. Output
  let branch = if head_ref.has_prefix("ref: refs/heads/") {
    trim_newline(hex_substr(head_ref, 16, head_ref.length() - 16))
  } else {
    "HEAD"
  }

  let short_hash = hex_substr(commit_hex, 0, 7)
  let is_root = parent_hash is None
  if is_root {
    stdout.write_string("[\{branch} (root-commit) \{short_hash}] \{message}\n")
  } else {
    stdout.write_string("[\{branch} \{short_hash}] \{message}\n")
  }

  0
}

///|
/// git write-tree
fn git_write_tree(
  ctx : @posix.PosixContext,
  _args : Array[String],
  stdout : StringBuilder,
  stderr : StringBuilder,
  exec : Executor,
) -> Int {
  let git_dir = ctx.resolve_path(".git")
  if !(ctx.get_fs().exists(git_dir)) {
    stderr.write_string("fatal: not a git repository\n")
    return 128
  }

  let index = exec.get_env().get_git_index()

  if index.length() == 0 {
    stderr.write_string("fatal: index is empty\n")
    return 128
  }

  // Build tree entries from index
  let entries : Array[@git.TreeEntry] = []
  for path, entry in index {
    let id = @git.ObjectId::from_hex(entry.hash) catch {
      _ => @git.ObjectId::zero()
    }
    entries.push(@git.TreeEntry::new(entry.mode, path, id))
  }

  // Create tree
  let (tree_id, compressed) = @git.create_tree(entries)
  let hex = tree_id.to_hex()

  // Store tree object
  exec
  .get_env()
  .store_git_object(hex, GitObject::{
    obj_type: "tree",
    size: 0,
    content: "",
    compressed,
  })

  stdout.write_string(hex)
  stdout.write_string("\n")
  0
}

///|
/// git commit-tree <tree> [-p <parent>] [-m <message>]
fn git_commit_tree(
  ctx : @posix.PosixContext,
  args : Array[String],
  stdout : StringBuilder,
  stderr : StringBuilder,
  exec : Executor,
) -> Int {
  let git_dir = ctx.resolve_path(".git")
  if !(ctx.get_fs().exists(git_dir)) {
    stderr.write_string("fatal: not a git repository\n")
    return 128
  }

  if args.length() == 0 {
    stderr.write_string(
      "usage: git commit-tree <tree> [-p <parent>] [-m <message>]\n",
    )
    return 1
  }

  let tree_hash = args[0]
  let mut parent_hash : String? = None
  let mut message = ""

  // Parse arguments
  let mut i = 1
  while i < args.length() {
    if args[i] == "-p" && i + 1 < args.length() {
      parent_hash = Some(args[i + 1])
      i += 2
    } else if args[i] == "-m" && i + 1 < args.length() {
      message = args[i + 1]
      i += 2
    } else {
      i += 1
    }
  }

  if message.length() == 0 {
    stderr.write_string("fatal: commit message required\n")
    return 1
  }

  // Build commit
  let tree_id = @git.ObjectId::from_hex(tree_hash) catch {
    _ => {
      stderr.write_string("fatal: not a valid tree: \{tree_hash}\n")
      return 128
    }
  }

  let parents : Array[@git.ObjectId] = match parent_hash {
    Some(h) => {
      let id = @git.ObjectId::from_hex(h) catch { _ => @git.ObjectId::zero() }
      [id]
    }
    None => []
  }

  // Get author from environment or use default
  let author = exec.get_env().get("GIT_AUTHOR_NAME").unwrap_or("User") +
    " <" +
    exec.get_env().get("GIT_AUTHOR_EMAIL").unwrap_or("user@example.com") +
    ">"

  let timestamp = 1700000000L // TODO: get real timestamp

  let commit = @git.Commit::new(
    tree_id,
    parents,
    author,
    timestamp,
    "+0000",
    author,
    timestamp,
    "+0000",
    message + "\n",
  )

  let (commit_id, compressed) = @git.create_commit(commit)
  let hex = commit_id.to_hex()

  // Store commit object
  exec
  .get_env()
  .store_git_object(hex, GitObject::{
    obj_type: "commit",
    size: 0,
    content: "",
    compressed,
  })

  // Update HEAD
  let head_ref = ctx.get_fs().read_string(git_dir + "/HEAD") catch {
      _ => "ref: refs/heads/main\n"
    }
  if head_ref.has_prefix("ref: ") {
    let ref_path = git_dir +
      "/" +
      trim_newline(hex_substr(head_ref, 5, head_ref.length() - 5))
    ctx.get_fs().write_string(ref_path, hex + "\n") catch {
      _ => ()
    }
  }

  stdout.write_string(hex)
  stdout.write_string("\n")
  0
}

///|
/// git log
fn git_log(
  ctx : @posix.PosixContext,
  _args : Array[String],
  stdout : StringBuilder,
  stderr : StringBuilder,
  exec : Executor,
) -> Int {
  let git_dir = ctx.resolve_path(".git")
  if !(ctx.get_fs().exists(git_dir)) {
    stderr.write_string("fatal: not a git repository\n")
    return 128
  }

  // Get HEAD
  let head_ref = ctx.get_fs().read_string(git_dir + "/HEAD") catch { _ => "" }

  let commit_hash = if head_ref.has_prefix("ref: ") {
    let ref_path = git_dir +
      "/" +
      trim_newline(hex_substr(head_ref, 5, head_ref.length() - 5))
    ctx.get_fs().read_string(ref_path) catch {
      _ => ""
    }
  } else {
    head_ref
  }

  let hash = trim_newline(commit_hash)
  if hash.length() == 0 {
    stderr.write_string("fatal: no commits yet\n")
    return 128
  }

  // Show commit
  let objects = exec.get_env().get_git_objects()
  match objects.get(hash) {
    Some(obj) => {
      stdout.write_string("commit \{hash}\n")
      stdout.write_string(obj.content)
      stdout.write_string("\n")
    }
    None => stdout.write_string("commit \{hash}\n")
  }

  0
}

///|
fn trim_newline(s : String) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new()
  for c in chars {
    if c != '\n' && c != '\r' {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn bytes_to_string(data : Bytes) -> String {
  let buf = StringBuilder::new()
  for b in data {
    buf.write_char(b.to_int().unsafe_to_char())
  }
  buf.to_string()
}

///|
/// Git object stored in memory
pub struct GitObject {
  obj_type : String
  size : Int
  content : String
  compressed : Bytes
}

///|
/// Index entry
pub struct IndexEntry {
  mode : String
  hash : String
  path : String
}
