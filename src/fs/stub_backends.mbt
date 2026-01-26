/// Stub backends for demonstration
/// Real implementations would connect to S3, SQLite, etc.

// ============ S3 Backend Stub ============

///|
/// S3-backed filesystem (stub implementation)
/// Real implementation would use AWS SDK
pub struct S3Backend {
  bucket : String
  prefix : String
  // In a real implementation:
  // client : S3Client
  // cache : Map[String, Bytes]

  // For stub: delegate to MemFS
  inner : MemFS
}

///|
pub fn S3Backend::new(bucket : String, prefix~ : String = "") -> S3Backend {
  { bucket, prefix, inner: MemFS::default() }
}

///|
pub impl FileSystem for S3Backend with exists(self, path) {
  // Real: HEAD object to S3
  self.inner.exists(path)
}

///|
pub impl FileSystem for S3Backend with is_dir(self, path) {
  self.inner.is_dir(path)
}

///|
pub impl FileSystem for S3Backend with is_file(self, path) {
  self.inner.is_file(path)
}

///|
pub impl FileSystem for S3Backend with is_symlink(self, path) {
  self.inner.is_symlink(path)
}

///|
pub impl FileSystem for S3Backend with resolve_path(self, path) {
  self.inner.resolve_path(path)
}

///|
pub impl FileSystem for S3Backend with read_file(self, path) {
  // Real: GetObject from S3
  self.inner.read_file(path)
}

///|
pub impl FileSystem for S3Backend with write_file(self, path, content) {
  // Real: PutObject to S3
  self.inner.write_file(path, content)
}

///|
pub impl FileSystem for S3Backend with read_string(self, path) {
  self.inner.read_string(path)
}

///|
pub impl FileSystem for S3Backend with write_string(self, path, content) {
  self.inner.write_string(path, content)
}

///|
pub impl FileSystem for S3Backend with truncate(self, path, length) {
  self.inner.truncate(path, length)
}

///|
pub impl FileSystem for S3Backend with size(self, path) {
  self.inner.size(path)
}

///|
pub impl FileSystem for S3Backend with remove(self, path) {
  // Real: DeleteObject from S3
  self.inner.remove(path)
}

///|
pub impl FileSystem for S3Backend with mkdir(self, path) {
  // S3 doesn't have real directories, but we can create marker objects
  self.inner.mkdir(path)
}

///|
pub impl FileSystem for S3Backend with mkdir_p(self, path) {
  self.inner.mkdir_p(path)
}

///|
pub impl FileSystem for S3Backend with rmdir(self, path) {
  self.inner.rmdir(path)
}

///|
pub impl FileSystem for S3Backend with readdir(self, path) {
  // Real: ListObjectsV2 with prefix
  self.inner.readdir(path)
}

///|
pub impl FileSystem for S3Backend with symlink(self, path, target) {
  // S3 doesn't support symlinks natively
  // Could store as metadata or special object
  self.inner.symlink(path, target)
}

///|
pub impl FileSystem for S3Backend with read_link(self, path) {
  self.inner.read_link(path)
}

///|
pub impl FileSystem for S3Backend with rename(self, old_path, new_path) {
  // Real: CopyObject + DeleteObject
  self.inner.rename(old_path, new_path)
}

///|
pub impl FileSystem for S3Backend with stat(self, path) {
  self.inner.stat(path)
}

// ============ SQLite Backend Stub ============

///|
/// SQLite-backed filesystem (stub implementation)
/// Real implementation would use SQLite database
pub struct SqliteBackend {
  db_path : String
  // In a real implementation:
  // conn : SqliteConnection

  // For stub: delegate to MemFS
  inner : MemFS
}

///|
pub fn SqliteBackend::new(db_path : String) -> SqliteBackend {
  { db_path, inner: MemFS::default() }
}

///|
pub impl FileSystem for SqliteBackend with exists(self, path) {
  // Real: SELECT 1 FROM files WHERE path = ?
  self.inner.exists(path)
}

///|
pub impl FileSystem for SqliteBackend with is_dir(self, path) {
  self.inner.is_dir(path)
}

///|
pub impl FileSystem for SqliteBackend with is_file(self, path) {
  self.inner.is_file(path)
}

///|
pub impl FileSystem for SqliteBackend with is_symlink(self, path) {
  self.inner.is_symlink(path)
}

///|
pub impl FileSystem for SqliteBackend with resolve_path(self, path) {
  self.inner.resolve_path(path)
}

///|
pub impl FileSystem for SqliteBackend with read_file(self, path) {
  // Real: SELECT content FROM files WHERE path = ?
  self.inner.read_file(path)
}

///|
pub impl FileSystem for SqliteBackend with write_file(self, path, content) {
  // Real: INSERT OR REPLACE INTO files (path, content, type) VALUES (?, ?, 'file')
  self.inner.write_file(path, content)
}

///|
pub impl FileSystem for SqliteBackend with read_string(self, path) {
  self.inner.read_string(path)
}

///|
pub impl FileSystem for SqliteBackend with write_string(self, path, content) {
  self.inner.write_string(path, content)
}

///|
pub impl FileSystem for SqliteBackend with truncate(self, path, length) {
  self.inner.truncate(path, length)
}

///|
pub impl FileSystem for SqliteBackend with size(self, path) {
  // Real: SELECT length(content) FROM files WHERE path = ?
  self.inner.size(path)
}

///|
pub impl FileSystem for SqliteBackend with remove(self, path) {
  // Real: DELETE FROM files WHERE path = ?
  self.inner.remove(path)
}

///|
pub impl FileSystem for SqliteBackend with mkdir(self, path) {
  // Real: INSERT INTO files (path, type) VALUES (?, 'dir')
  self.inner.mkdir(path)
}

///|
pub impl FileSystem for SqliteBackend with mkdir_p(self, path) {
  self.inner.mkdir_p(path)
}

///|
pub impl FileSystem for SqliteBackend with rmdir(self, path) {
  self.inner.rmdir(path)
}

///|
pub impl FileSystem for SqliteBackend with readdir(self, path) {
  // Real: SELECT name FROM files WHERE parent = ?
  self.inner.readdir(path)
}

///|
pub impl FileSystem for SqliteBackend with symlink(self, path, target) {
  // Real: INSERT INTO files (path, target, type) VALUES (?, ?, 'symlink')
  self.inner.symlink(path, target)
}

///|
pub impl FileSystem for SqliteBackend with read_link(self, path) {
  self.inner.read_link(path)
}

///|
pub impl FileSystem for SqliteBackend with rename(self, old_path, new_path) {
  // Real: UPDATE files SET path = ? WHERE path = ?
  self.inner.rename(old_path, new_path)
}

///|
pub impl FileSystem for SqliteBackend with stat(self, path) {
  self.inner.stat(path)
}
