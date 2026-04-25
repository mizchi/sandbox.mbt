/// Host filesystem backend
/// Uses callbacks to access the actual host filesystem
/// The host environment provides implementations via the HostFsOps struct

///|
/// Host filesystem operations interface
/// The host environment creates this with actual implementations
pub(all) struct HostFsOps {
  exists : (String) -> Bool
  is_dir : (String) -> Bool
  is_file : (String) -> Bool
  is_symlink : (String) -> Bool
  read_file : (String) -> Bytes?
  write_file : (String, Bytes) -> Bool
  read_string : (String) -> String?
  write_string : (String, String) -> Bool
  size : (String) -> Int // -1 on error
  remove : (String) -> Bool
  mkdir : (String) -> Bool
  mkdir_p : (String) -> Bool
  rmdir : (String) -> Bool
  readdir : (String) -> Array[String]?
  symlink : (String, String) -> Bool // (link_path, target)
  read_link : (String) -> String?
  rename : (String, String) -> Bool // (old, new)
  truncate : (String, Int) -> Bool // (path, length)
  resolve_path : (String) -> String?
}

///|
/// Create stub ops that always fail (for testing)
pub fn HostFsOps::stub() -> HostFsOps {
  {
    exists: fn(_) { false },
    is_dir: fn(_) { false },
    is_file: fn(_) { false },
    is_symlink: fn(_) { false },
    read_file: fn(_) { None },
    write_file: fn(_, _) { false },
    read_string: fn(_) { None },
    write_string: fn(_, _) { false },
    size: fn(_) { -1 },
    remove: fn(_) { false },
    mkdir: fn(_) { false },
    mkdir_p: fn(_) { false },
    rmdir: fn(_) { false },
    readdir: fn(_) { None },
    symlink: fn(_, _) { false },
    read_link: fn(_) { None },
    rename: fn(_, _) { false },
    truncate: fn(_, _) { false },
    resolve_path: fn(_) { None },
  }
}

// ============ HostFs Implementation ============

///|
/// Host filesystem backend
/// Delegates all operations to the provided HostFsOps
pub struct HostFs {
  ops : HostFsOps
  /// Base path prefix (for sandboxing)
  base_path : String
}

///|
/// Create a new host filesystem backend
pub fn HostFs::new(ops : HostFsOps, base_path? : String = "") -> HostFs {
  { ops, base_path }
}

///|
/// Get the full path with base prefix
fn HostFs::full_path(self : HostFs, path : String) -> String {
  if self.base_path.is_empty() {
    path
  } else {
    self.base_path + path
  }
}

///|
pub impl FileSystem for HostFs with exists(self, path) {
  (self.ops.exists)(self.full_path(path))
}

///|
pub impl FileSystem for HostFs with is_dir(self, path) {
  (self.ops.is_dir)(self.full_path(path))
}

///|
pub impl FileSystem for HostFs with is_file(self, path) {
  (self.ops.is_file)(self.full_path(path))
}

///|
pub impl FileSystem for HostFs with is_symlink(self, path) {
  (self.ops.is_symlink)(self.full_path(path))
}

///|
pub impl FileSystem for HostFs with resolve_path(self, path) {
  let full = self.full_path(path)
  match (self.ops.resolve_path)(full) {
    Some(resolved) => resolved
    None => raise FsError::InvalidPath("Failed to resolve path: " + path)
  }
}

///|
pub impl FileSystem for HostFs with read_file(self, path) {
  match (self.ops.read_file)(self.full_path(path)) {
    Some(content) => content
    None => raise FsError::NotFound(path)
  }
}

///|
pub impl FileSystem for HostFs with write_file(self, path, content) {
  if !((self.ops.write_file)(self.full_path(path), content)) {
    raise FsError::InvalidPath("Failed to write file: " + path)
  }
}

///|
pub impl FileSystem for HostFs with read_string(self, path) {
  match (self.ops.read_string)(self.full_path(path)) {
    Some(content) => content
    None => raise FsError::NotFound(path)
  }
}

///|
pub impl FileSystem for HostFs with write_string(self, path, content) {
  if !((self.ops.write_string)(self.full_path(path), content)) {
    raise FsError::InvalidPath("Failed to write file: " + path)
  }
}

///|
pub impl FileSystem for HostFs with truncate(self, path, length) {
  if !((self.ops.truncate)(self.full_path(path), length)) {
    raise FsError::InvalidPath("Failed to truncate file: " + path)
  }
}

///|
pub impl FileSystem for HostFs with size(self, path) {
  let s = (self.ops.size)(self.full_path(path))
  if s >= 0 {
    Some(s)
  } else {
    None
  }
}

///|
pub impl FileSystem for HostFs with remove(self, path) {
  if !((self.ops.remove)(self.full_path(path))) {
    raise FsError::InvalidPath("Failed to remove file: " + path)
  }
}

///|
pub impl FileSystem for HostFs with mkdir(self, path) {
  if !((self.ops.mkdir)(self.full_path(path))) {
    raise FsError::InvalidPath("Failed to create directory: " + path)
  }
}

///|
pub impl FileSystem for HostFs with mkdir_p(self, path) {
  if !((self.ops.mkdir_p)(self.full_path(path))) {
    raise FsError::InvalidPath("Failed to create directory: " + path)
  }
}

///|
pub impl FileSystem for HostFs with rmdir(self, path) {
  if !((self.ops.rmdir)(self.full_path(path))) {
    raise FsError::InvalidPath("Failed to remove directory: " + path)
  }
}

///|
pub impl FileSystem for HostFs with readdir(self, path) {
  match (self.ops.readdir)(self.full_path(path)) {
    Some(entries) => entries
    None => raise FsError::NotFound(path)
  }
}

///|
pub impl FileSystem for HostFs with symlink(self, path, target) {
  if !((self.ops.symlink)(self.full_path(path), target)) {
    raise FsError::InvalidPath("Failed to create symlink: " + path)
  }
}

///|
pub impl FileSystem for HostFs with read_link(self, path) {
  match (self.ops.read_link)(self.full_path(path)) {
    Some(target) => target
    None => raise FsError::NotFound(path)
  }
}

///|
pub impl FileSystem for HostFs with rename(self, old_path, new_path) {
  if !((self.ops.rename)(self.full_path(old_path), self.full_path(new_path))) {
    raise FsError::InvalidPath(
      "Failed to rename: " + old_path + " -> " + new_path,
    )
  }
}

///|
pub impl FileSystem for HostFs with stat(self, path) {
  let full = self.full_path(path)
  if !((self.ops.exists)(full)) {
    raise FsError::NotFound(path)
  }
  if (self.ops.is_symlink)(full) {
    FileStat::symlink()
  } else if (self.ops.is_dir)(full) {
    FileStat::dir()
  } else {
    let size = (self.ops.size)(full)
    FileStat::file(if size >= 0 { size } else { 0 })
  }
}
