/// FileSystem trait - Abstract interface for filesystem backends
/// Implementations: MemFS (in-memory), S3Backend, SqliteBackend, etc.

///|
/// File metadata returned by stat operations
pub struct FileStat {
  size : Int
  is_dir : Bool
  is_file : Bool
  is_symlink : Bool
}

///|
pub fn FileStat::file(size : Int) -> FileStat {
  { size, is_dir: false, is_file: true, is_symlink: false }
}

///|
pub fn FileStat::dir() -> FileStat {
  { size: 0, is_dir: true, is_file: false, is_symlink: false }
}

///|
pub fn FileStat::symlink() -> FileStat {
  { size: 0, is_dir: false, is_file: false, is_symlink: true }
}

///|
/// Abstract filesystem interface
/// All paths are assumed to be absolute and normalized
pub trait FileSystem {
  // Existence checks
  exists(Self, String) -> Bool
  is_dir(Self, String) -> Bool
  is_file(Self, String) -> Bool
  is_symlink(Self, String) -> Bool

  // Path resolution (for symlinks)
  resolve_path(Self, String) -> String raise FsError

  // File operations
  read_file(Self, String) -> Bytes raise FsError
  write_file(Self, String, Bytes) -> Unit raise FsError
  read_string(Self, String) -> String raise FsError
  write_string(Self, String, String) -> Unit raise FsError
  truncate(Self, String, Int) -> Unit raise FsError
  size(Self, String) -> Int?
  remove(Self, String) -> Unit raise FsError

  // Directory operations
  mkdir(Self, String) -> Unit raise FsError
  mkdir_p(Self, String) -> Unit raise FsError
  rmdir(Self, String) -> Unit raise FsError
  readdir(Self, String) -> Array[String] raise FsError

  // Symlink operations
  symlink(Self, String, String) -> Unit raise FsError
  read_link(Self, String) -> String raise FsError

  // Move/Rename
  rename(Self, String, String) -> Unit raise FsError

  // Stat
  stat(Self, String) -> FileStat raise FsError
}
