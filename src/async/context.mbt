/// SandboxContext - Async API for sandbox operations
///
/// Design notes:
/// - Wraps MemfsBackend with async interface
/// - WASI 0.3 Task concept preparation (future extension)
/// - Cooperative scheduling via coroutine

/// Async sandbox context
pub struct SandboxContext {
  backend : @runtime.MemfsBackend
  // Future: task_id, waitables, backpressure
}

/// Create a new sandbox context
pub fn SandboxContext::new() -> SandboxContext {
  { backend: @runtime.MemfsBackend::new() }
}

/// Create with existing backend
pub fn SandboxContext::with_backend(backend : @runtime.MemfsBackend) -> SandboxContext {
  { backend }
}

/// Get the underlying backend (for interop)
pub fn SandboxContext::backend(self : SandboxContext) -> @runtime.MemfsBackend {
  self.backend
}

// ============ Filesystem operations ============

/// Open a file
pub async fn SandboxContext::open(
  self : SandboxContext,
  path : String,
  flags : @runtime.OpenFlags
) -> @runtime.Fd raise @runtime.IOError {
  self.backend.open(path, flags)
}

/// Read from a file descriptor
pub async fn SandboxContext::read(
  self : SandboxContext,
  fd : @runtime.Fd,
  len : Int
) -> Bytes raise @runtime.IOError {
  self.backend.read(fd, len)
}

/// Write to a file descriptor
pub async fn SandboxContext::write(
  self : SandboxContext,
  fd : @runtime.Fd,
  data : Bytes
) -> Int raise @runtime.IOError {
  self.backend.write(fd, data)
}

/// Close a file descriptor
pub async fn SandboxContext::close(
  self : SandboxContext,
  fd : @runtime.Fd
) -> Unit raise @runtime.IOError {
  self.backend.close(fd)
}

/// Get file stats
pub async fn SandboxContext::stat(
  self : SandboxContext,
  path : String
) -> @runtime.FileStat raise @runtime.IOError {
  self.backend.stat(path)
}

/// Check if path exists
pub async fn SandboxContext::exists(self : SandboxContext, path : String) -> Bool {
  self.backend.exists(path)
}

/// Create directory
pub async fn SandboxContext::mkdir(
  self : SandboxContext,
  path : String
) -> Unit raise @runtime.IOError {
  self.backend.mkdir(path)
}

/// Read directory contents
pub async fn SandboxContext::readdir(
  self : SandboxContext,
  path : String
) -> Array[@runtime.DirEntry] raise @runtime.IOError {
  self.backend.readdir(path)
}

/// Remove a file
pub async fn SandboxContext::unlink(
  self : SandboxContext,
  path : String
) -> Unit raise @runtime.IOError {
  self.backend.unlink(path)
}

/// Rename a file
pub async fn SandboxContext::rename(
  self : SandboxContext,
  from : String,
  to : String
) -> Unit raise @runtime.IOError {
  self.backend.rename(from, to)
}

// ============ High-level file operations ============

/// Read entire file as bytes
pub async fn SandboxContext::read_file(
  self : SandboxContext,
  path : String
) -> Bytes raise @runtime.IOError {
  let fd = self.open(path, @runtime.OpenFlags::read_only())
  let stat = self.stat(path)
  let data = self.read(fd, stat.size.to_int())
  self.close(fd)
  data
}

/// Read entire file as string
pub async fn SandboxContext::read_text(
  self : SandboxContext,
  path : String
) -> String raise @runtime.IOError {
  let data = self.read_file(path)
  // Simple UTF-8 decode (lossy)
  let chars : Array[Char] = []
  for i in 0..<data.length() {
    chars.push(Char::from_int(data[i].to_int()))
  }
  String::from_array(chars)
}

/// Write bytes to file (create or truncate)
pub async fn SandboxContext::write_file(
  self : SandboxContext,
  path : String,
  data : Bytes
) -> Unit raise @runtime.IOError {
  let flags : @runtime.OpenFlags = {
    read: false,
    write: true,
    append: false,
    create: true,
    truncate: true,
    exclusive: false,
  }
  let fd = self.open(path, flags)
  let _ = self.write(fd, data)
  self.close(fd)
}

/// Write string to file
pub async fn SandboxContext::write_text(
  self : SandboxContext,
  path : String,
  content : String
) -> Unit raise @runtime.IOError {
  let bytes = Bytes::from_iter(content.iter().map(fn(c) { c.to_int().to_byte() }))
  self.write_file(path, bytes)
}

// ============ Environment operations ============

/// Get environment variable
pub fn SandboxContext::get_env(self : SandboxContext, name : String) -> String? {
  self.backend.get_env(name)
}

/// Set environment variable
pub fn SandboxContext::set_env(
  self : SandboxContext,
  name : String,
  value : String
) -> Unit {
  self.backend.set_env(name, value)
}

/// Get current working directory
pub fn SandboxContext::cwd(self : SandboxContext) -> String {
  self.backend.cwd()
}

/// Change current working directory
pub async fn SandboxContext::chdir(
  self : SandboxContext,
  path : String
) -> Unit raise @runtime.IOError {
  self.backend.chdir(path)
}

// ============ Process operations ============

/// Spawn a process
pub async fn SandboxContext::spawn(
  self : SandboxContext,
  cmd : @runtime.Command
) -> @runtime.Process raise @runtime.ProcessError {
  self.backend.spawn(cmd)
}

/// Wait for process to complete
pub async fn SandboxContext::wait(
  self : SandboxContext,
  pid : @runtime.Pid
) -> @runtime.ExitStatus raise @runtime.ProcessError {
  self.backend.wait(pid)
}

/// Read stdout from process
pub async fn SandboxContext::read_stdout(
  self : SandboxContext,
  pid : @runtime.Pid
) -> String raise @runtime.ProcessError {
  self.backend.read_stdout(pid)
}

/// Read stderr from process
pub async fn SandboxContext::read_stderr(
  self : SandboxContext,
  pid : @runtime.Pid
) -> String raise @runtime.ProcessError {
  self.backend.read_stderr(pid)
}

// ============ Stream creation ============

/// Create a new byte stream pair
pub fn SandboxContext::create_stream(_self : SandboxContext) -> (ReadEnd, WriteEnd) {
  new_byte_stream()
}
