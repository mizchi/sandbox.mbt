/// Fs - In-memory filesystem for sandboxed operations

///|
/// Entry type in the filesystem
pub(all) enum FsEntry {
  File(Bytes)
  Dir
  Symlink(String)
}

///|
/// Error types for Fs operations
pub(all) suberror FsError {
  NotFound(String)
  AlreadyExists(String)
  NotAFile(String)
  NotADirectory(String)
  InvalidPath(String)
  SymlinkLoop(String)
} derive(Show, Eq)

///|
/// In-memory filesystem
pub struct Fs {
  entries : Map[String, FsEntry]
  mut current_size : Int
  max_total_size : Int?
  max_file_count : Int?
}

///|
/// Create a new Fs
pub fn Fs::new(max_total_size? : Int, max_file_count? : Int) -> Fs {
  let fs : Fs = { entries: {}, current_size: 0, max_total_size, max_file_count }
  // Create root directory
  fs.entries.set("/", Dir)
  fs
}

///|
/// Default Fs with standard directories
pub fn Fs::default() -> Fs {
  let fs = Fs::new()
  try {
    fs.mkdir("/bin")
    fs.mkdir("/home")
    fs.mkdir("/tmp")
  } catch {
    _ => ()
  }
  fs
}

///|
/// Normalize path (remove . and ..)
fn normalize_path(path : String) -> String {
  if path == "" {
    return "/"
  }
  let parts = split_path(path)
  let result : Array[String] = []
  for part in parts {
    if part == "" || part == "." {
      continue
    } else if part == ".." {
      if result.length() > 0 {
        ignore(result.pop())
      }
    } else {
      result.push(part)
    }
  }
  if result.length() == 0 {
    "/"
  } else {
    "/" + result.join("/")
  }
}

///|
fn split_path(path : String) -> Array[String] {
  let result : Array[String] = []
  let mut current = StringBuilder::new()
  for c in path {
    if c == '/' {
      if current.to_string().length() > 0 {
        result.push(current.to_string())
        current = StringBuilder::new()
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
fn parent_path(path : String) -> String {
  let normalized = normalize_path(path)
  if normalized == "/" {
    return "/"
  }
  match normalized.rev_find("/") {
    None => "/"
    Some(0) => "/"
    Some(i) => {
      let result = StringBuilder::new()
      let chars = normalized.to_array()
      for j in 0..<i {
        result.write_char(chars[j])
      }
      result.to_string()
    }
  }
}

///|
/// Resolve symlinks (up to max depth)
fn Fs::resolve_symlinks(
  self : Fs,
  path : String,
  max_depth : Int,
) -> String raise FsError {
  if max_depth <= 0 {
    raise SymlinkLoop(path)
  }
  match self.entries.get(path) {
    Some(Symlink(target)) => {
      let resolved = if target.has_prefix("/") {
        normalize_path(target)
      } else {
        normalize_path(parent_path(path) + "/" + target)
      }
      self.resolve_symlinks(resolved, max_depth - 1)
    }
    _ => path
  }
}

///|
/// Resolve path following symlinks
pub fn Fs::resolve_path(self : Fs, path : String) -> String raise FsError {
  self.resolve_symlinks(normalize_path(path), 40)
}

///|
/// Check if path exists
pub fn Fs::exists(self : Fs, path : String) -> Bool {
  let normalized = normalize_path(path)
  self.entries.contains(normalized)
}

///|
/// Check if path is a directory
pub fn Fs::is_dir(self : Fs, path : String) -> Bool {
  let normalized = normalize_path(path)
  match self.entries.get(normalized) {
    Some(Dir) => true
    Some(Symlink(_)) => {
      let resolved = self.resolve_path(normalized) catch { _ => return false }
      match self.entries.get(resolved) {
        Some(Dir) => true
        _ => false
      }
    }
    _ => false
  }
}

///|
/// Check if path is a file
pub fn Fs::is_file(self : Fs, path : String) -> Bool {
  let normalized = normalize_path(path)
  match self.entries.get(normalized) {
    Some(File(_)) => true
    Some(Symlink(_)) => {
      let resolved = self.resolve_path(normalized) catch { _ => return false }
      match self.entries.get(resolved) {
        Some(File(_)) => true
        _ => false
      }
    }
    _ => false
  }
}

///|
/// Check if path is a symlink
pub fn Fs::is_symlink(self : Fs, path : String) -> Bool {
  let normalized = normalize_path(path)
  match self.entries.get(normalized) {
    Some(Symlink(_)) => true
    _ => false
  }
}

///|
/// Create a directory
pub fn Fs::mkdir(self : Fs, path : String) -> Unit raise FsError {
  let normalized = normalize_path(path)
  if normalized == "/" {
    return
  }
  // Check parent exists
  let parent = parent_path(normalized)
  if not(self.is_dir(parent)) {
    raise NotADirectory(parent)
  }
  // Check path doesn't exist
  if self.exists(normalized) {
    raise AlreadyExists(normalized)
  }
  self.entries.set(normalized, Dir)
}

///|
/// Create directories recursively
pub fn Fs::mkdir_p(self : Fs, path : String) -> Unit raise FsError {
  let normalized = normalize_path(path)
  if normalized == "/" {
    return
  }
  let parts = split_path(normalized)
  let mut current = ""
  for part in parts {
    current = current + "/" + part
    if not(self.exists(current)) {
      self.entries.set(current, Dir)
    } else if not(self.is_dir(current)) {
      raise NotADirectory(current)
    }
  }
}

///|
/// Read file contents
pub fn Fs::read_file(self : Fs, path : String) -> Bytes raise FsError {
  let resolved = self.resolve_path(path)
  match self.entries.get(resolved) {
    Some(File(content)) => content
    Some(Dir) => raise NotAFile(resolved)
    Some(Symlink(_)) => raise NotAFile(resolved)
    None => raise NotFound(path)
  }
}

///|
/// Write file contents
pub fn Fs::write_file(
  self : Fs,
  path : String,
  content : Bytes,
) -> Unit raise FsError {
  let normalized = normalize_path(path)
  // Check parent exists
  let parent = parent_path(normalized)
  if not(self.is_dir(parent)) {
    raise NotADirectory(parent)
  }
  // Get old size for quota tracking
  let old_size = match self.entries.get(normalized) {
    Some(File(old)) => old.length()
    Some(Dir) => raise NotAFile(normalized)
    _ => 0
  }
  self.current_size = self.current_size - old_size + content.length()
  self.entries.set(normalized, File(content))
}

///|
/// Write string to file
pub fn Fs::write_string(
  self : Fs,
  path : String,
  content : String,
) -> Unit raise FsError {
  self.write_file(
    path,
    Bytes::from_iter(content.iter().map(fn(c) { c.to_int().to_byte() })),
  )
}

///|
/// Read file as string
pub fn Fs::read_string(self : Fs, path : String) -> String raise FsError {
  let bytes = self.read_file(path)
  let result = StringBuilder::new()
  for b in bytes {
    result.write_char(b.to_int().unsafe_to_char())
  }
  result.to_string()
}

///|
/// Create symlink
pub fn Fs::symlink(
  self : Fs,
  path : String,
  target : String,
) -> Unit raise FsError {
  let normalized = normalize_path(path)
  let parent = parent_path(normalized)
  if not(self.is_dir(parent)) {
    raise NotADirectory(parent)
  }
  if self.exists(normalized) {
    raise AlreadyExists(normalized)
  }
  self.entries.set(normalized, Symlink(target))
}

///|
/// Read symlink target
pub fn Fs::read_link(self : Fs, path : String) -> String raise FsError {
  let normalized = normalize_path(path)
  match self.entries.get(normalized) {
    Some(Symlink(target)) => target
    Some(_) => raise NotAFile(normalized)
    None => raise NotFound(path)
  }
}

///|
/// Remove file or symlink
pub fn Fs::remove(self : Fs, path : String) -> Unit raise FsError {
  let normalized = normalize_path(path)
  match self.entries.get(normalized) {
    Some(File(content)) => {
      self.current_size -= content.length()
      self.entries.remove(normalized)
    }
    Some(Symlink(_)) => self.entries.remove(normalized)
    Some(Dir) => raise NotAFile(normalized)
    None => raise NotFound(path)
  }
}

///|
/// Remove directory (must be empty)
pub fn Fs::rmdir(self : Fs, path : String) -> Unit raise FsError {
  let normalized = normalize_path(path)
  if normalized == "/" {
    raise InvalidPath("/")
  }
  if not(self.is_dir(normalized)) {
    raise NotADirectory(normalized)
  }
  // Check if empty
  for entry_path, _ in self.entries {
    if entry_path != normalized && entry_path.has_prefix(normalized + "/") {
      raise NotADirectory(normalized + " is not empty")
    }
  }
  self.entries.remove(normalized)
}

///|
/// List directory contents
pub fn Fs::readdir(self : Fs, path : String) -> Array[String] raise FsError {
  let resolved = self.resolve_path(path)
  if not(self.is_dir(resolved)) {
    raise NotADirectory(path)
  }
  let prefix = if resolved == "/" { "/" } else { resolved + "/" }
  let result : Array[String] = []
  for entry_path, _ in self.entries {
    if entry_path.has_prefix(prefix) {
      let rest = substring_from(entry_path, prefix.length())
      if rest.length() > 0 && not(string_contains(rest, "/")) {
        result.push(rest)
      }
    }
  }
  result
}

///|
/// Get file size
pub fn Fs::size(self : Fs, path : String) -> Int? {
  let resolved = self.resolve_path(path) catch { _ => return None }
  match self.entries.get(resolved) {
    Some(File(content)) => Some(content.length())
    _ => None
  }
}

///|
/// Rename (move) a file or directory
pub fn Fs::rename(
  self : Fs,
  old_path : String,
  new_path : String,
) -> Unit raise FsError {
  let old_normalized = normalize_path(old_path)
  let new_normalized = normalize_path(new_path)
  if old_normalized == "/" || new_normalized == "/" {
    raise InvalidPath("Cannot rename root")
  }

  // Check source exists
  if not(self.exists(old_normalized)) {
    raise NotFound(old_path)
  }

  // Check new parent exists and is a directory
  let new_parent = parent_path(new_normalized)
  if not(self.exists(new_parent)) {
    raise NotFound(new_parent)
  }
  if not(self.is_dir(new_parent)) {
    raise NotADirectory(new_parent)
  }

  // If destination exists, remove it first (for files)
  if self.exists(new_normalized) {
    if self.is_dir(new_normalized) && not(self.is_dir(old_normalized)) {
      raise NotAFile(new_normalized)
    }
    if self.is_file(new_normalized) || self.is_symlink(new_normalized) {
      self.entries.remove(new_normalized)
    }
  }

  // If source is a directory, rename all entries under it
  if self.is_dir(old_normalized) {
    // Collect all entries that need to be moved
    let to_move : Array[(String, FsEntry)] = []
    for entry_path, entry in self.entries {
      if entry_path == old_normalized ||
        entry_path.has_prefix(old_normalized + "/") {
        to_move.push((entry_path, entry))
      }
    }

    // Remove old entries and add new ones
    for item in to_move {
      let (entry_path, entry) = item
      self.entries.remove(entry_path)

      // Calculate new path
      let new_entry_path = if entry_path == old_normalized {
        new_normalized
      } else {
        let suffix = substring_from(entry_path, old_normalized.length())
        new_normalized + suffix
      }
      self.entries.set(new_entry_path, entry)
    }
  } else {
    // File or symlink - simple move
    match self.entries.get(old_normalized) {
      Some(entry) => {
        self.entries.remove(old_normalized)
        self.entries.set(new_normalized, entry)
      }
      None => raise NotFound(old_path)
    }
  }
}

///|
/// Truncate a file to specified length
pub fn Fs::truncate(
  self : Fs,
  path : String,
  length : Int,
) -> Unit raise FsError {
  let normalized = normalize_path(path)
  match self.entries.get(normalized) {
    Some(File(content)) => {
      let old_len = content.length()
      if length == old_len {
        // No change needed
        return
      }

      // Use FixedArray for efficient copy
      let new_content = FixedArray::make(length, b'\x00')
      if length < old_len {
        // Shrink: copy only what we need
        for i in 0..<length {
          new_content[i] = content[i]
        }
      } else {
        // Extend: copy existing content, rest is already zero
        for i in 0..<old_len {
          new_content[i] = content[i]
        }
      }
      self.current_size = self.current_size - old_len + length
      self.entries.set(normalized, File(Bytes::from_array(new_content[:])))
    }
    Some(Dir) => raise NotAFile(normalized)
    Some(Symlink(_)) => {
      // Follow symlink and truncate target
      let resolved = self.resolve_path(normalized)
      self.truncate(resolved, length)
    }
    None => raise NotFound(path)
  }
}

///|
/// Get total size of all files
pub fn Fs::total_size(self : Fs) -> Int {
  self.current_size
}

///|
/// Get file count
pub fn Fs::file_count(self : Fs) -> Int {
  let mut count = 0
  for _, entry in self.entries {
    match entry {
      File(_) => count += 1
      _ => ()
    }
  }
  count
}

///|
fn substring_from(s : String, start : Int) -> String {
  if start >= s.length() {
    return ""
  }
  let result = StringBuilder::new()
  let chars = s.to_array()
  for i in start..<chars.length() {
    result.write_char(chars[i])
  }
  result.to_string()
}

///|
fn string_contains(s : String, sub : String) -> Bool {
  s.find(sub) is Some(_)
}

///|
/// Get file/directory stat
pub fn Fs::stat(self : Fs, path : String) -> FileStat raise FsError {
  let resolved = self.resolve_path(path)
  match self.entries.get(resolved) {
    Some(File(content)) => FileStat::file(content.length())
    Some(Dir) => FileStat::dir()
    Some(Symlink(_)) => FileStat::symlink()
    None => raise NotFound(path)
  }
}

// ============ FileSystem Trait Implementation ============

///|
pub impl FileSystem for Fs with exists(self, path) {
  self.exists(path)
}

///|
pub impl FileSystem for Fs with is_dir(self, path) {
  self.is_dir(path)
}

///|
pub impl FileSystem for Fs with is_file(self, path) {
  self.is_file(path)
}

///|
pub impl FileSystem for Fs with is_symlink(self, path) {
  self.is_symlink(path)
}

///|
pub impl FileSystem for Fs with resolve_path(self, path) {
  self.resolve_path(path)
}

///|
pub impl FileSystem for Fs with read_file(self, path) {
  self.read_file(path)
}

///|
pub impl FileSystem for Fs with write_file(self, path, content) {
  self.write_file(path, content)
}

///|
pub impl FileSystem for Fs with read_string(self, path) {
  self.read_string(path)
}

///|
pub impl FileSystem for Fs with write_string(self, path, content) {
  self.write_string(path, content)
}

///|
pub impl FileSystem for Fs with truncate(self, path, length) {
  self.truncate(path, length)
}

///|
pub impl FileSystem for Fs with size(self, path) {
  self.size(path)
}

///|
pub impl FileSystem for Fs with remove(self, path) {
  self.remove(path)
}

///|
pub impl FileSystem for Fs with mkdir(self, path) {
  self.mkdir(path)
}

///|
pub impl FileSystem for Fs with mkdir_p(self, path) {
  self.mkdir_p(path)
}

///|
pub impl FileSystem for Fs with rmdir(self, path) {
  self.rmdir(path)
}

///|
pub impl FileSystem for Fs with readdir(self, path) {
  self.readdir(path)
}

///|
pub impl FileSystem for Fs with symlink(self, path, target) {
  self.symlink(path, target)
}

///|
pub impl FileSystem for Fs with read_link(self, path) {
  self.read_link(path)
}

///|
pub impl FileSystem for Fs with rename(self, old_path, new_path) {
  self.rename(old_path, new_path)
}

///|
pub impl FileSystem for Fs with stat(self, path) {
  self.stat(path)
}
