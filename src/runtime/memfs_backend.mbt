/// MemFS Backend - Pure in-memory implementation

/// Process execution context passed to handlers
pub struct ProcessContext {
  backend : MemfsBackend
  args : Array[String]
  io : ProcessIO
}

///|
pub fn ProcessContext::write_stdout(self : ProcessContext, s : String) -> Unit {
  match self.io.stdout {
    Some(pipe) => {
      let _ = pipe.write_string(s)

    }
    None => ()
  }
}

///|
pub fn ProcessContext::write_stderr(self : ProcessContext, s : String) -> Unit {
  match self.io.stderr {
    Some(pipe) => {
      let _ = pipe.write_string(s)

    }
    None => ()
  }
}

///|
pub fn ProcessContext::read_stdin(self : ProcessContext) -> String {
  match self.io.stdin {
    Some(pipe) => pipe.read_string()
    None => ""
  }
}

/// MemFS Backend
pub struct MemfsBackend {
  fs : @fs.MemFS
  // File descriptor table
  fd_table : Map[Fd, OpenFileState]
  mut next_fd : Int
  // Process management
  processes : Map[Pid, ProcessState]
  mut next_pid : Int
  current_pid : Pid
  // Process registry (command name -> handler function)
  registry : Map[String, (ProcessContext) -> Int]
  // Environment
  env : Map[String, String]
  mut cwd : String
  args : Array[String]
}

/// Internal open file state
struct OpenFileState {
  path : String
  flags : OpenFlags
  mut offset : Int64
  mut closed : Bool
}

/// Internal process state
struct ProcessState {
  pid : Pid
  io : ProcessIO
  mut exit_code : Int?
}

///|
pub fn MemfsBackend::new() -> MemfsBackend {
  let backend : MemfsBackend = {
    fs: @fs.MemFS::new(),
    fd_table: {},
    next_fd: 3, // 0,1,2 reserved
    processes: {},
    next_pid: 2,
    current_pid: Pid(1),
    registry: {},
    env: {},
    cwd: "/",
    args: [],
  }
  // Default environment
  backend.env.set("HOME", "/home")
  backend.env.set("PATH", "/bin:/usr/bin")
  backend.env.set("USER", "user")
  backend.env.set("PWD", "/")
  backend
}

///|
pub fn MemfsBackend::with_fs(fs : @fs.MemFS) -> MemfsBackend {
  let backend = MemfsBackend::new()
  { ..backend, fs }
}

///|
pub fn MemfsBackend::register(
  self : MemfsBackend,
  name : String,
  handler : (ProcessContext) -> Int
) -> Unit {
  self.registry.set(name, handler)
}

// ============ Helper functions ============

///|
fn MemfsBackend::resolve_path(self : MemfsBackend, path : String) -> String {
  if path.has_prefix("/") {
    path
  } else {
    let cwd = self.cwd
    if cwd == "/" {
      "/" + path
    } else {
      cwd + "/" + path
    }
  }
}

///|
fn MemfsBackend::alloc_fd(self : MemfsBackend) -> Fd {
  let fd = Fd(self.next_fd)
  self.next_fd += 1
  fd
}

///|
fn MemfsBackend::get_file(
  self : MemfsBackend,
  fd : Fd
) -> OpenFileState raise IOError {
  match self.fd_table.get(fd) {
    Some(f) => {
      if f.closed {
        raise IOError::Closed
      }
      f
    }
    None => raise IOError::InvalidInput("Bad file descriptor: \{fd}")
  }
}

///|
fn convert_memfs_error(e : @fs.MemFSError) -> IOError {
  match e {
    @fs.MemFSError::NotFound(p) => IOError::NotFound(p)
    @fs.MemFSError::AlreadyExists(p) => IOError::AlreadyExists(p)
    @fs.MemFSError::NotAFile(p) => IOError::InvalidInput("Not a file: \{p}")
    @fs.MemFSError::NotADirectory(p) => IOError::NotDirectory(p)
    @fs.MemFSError::InvalidPath(p) => IOError::InvalidInput("Invalid path: \{p}")
    @fs.MemFSError::SymlinkLoop(p) =>
      IOError::InvalidInput("Symlink loop: \{p}")
  }
}

// ============ Filesystem implementation ============

///|
pub impl Filesystem for MemfsBackend with open(self, path, flags) {
  let abs_path = self.resolve_path(path)
  let exists = self.fs.exists(abs_path)

  if flags.create {
    if not(exists) {
      self.fs.write_string(abs_path, "") catch {
        e => raise convert_memfs_error(e)
      }
    }
  } else if not(exists) {
    raise IOError::NotFound(abs_path)
  }

  if self.fs.is_dir(abs_path) && flags.is_writable() {
    raise IOError::IsDirectory(abs_path)
  }

  if flags.truncate && flags.is_writable() && not(self.fs.is_dir(abs_path)) {
    self.fs.write_string(abs_path, "") catch { e => raise convert_memfs_error(e) }
  }

  let fd = self.alloc_fd()
  let state : OpenFileState = {
    path: abs_path,
    flags,
    offset: 0L,
    closed: false,
  }

  if flags.append {
    match self.fs.size(abs_path) {
      Some(size) => state.offset = size.to_int64()
      None => ()
    }
  }

  self.fd_table.set(fd, state)
  fd
}

///|
pub impl Filesystem for MemfsBackend with read(self, fd, len) {
  let file = self.get_file(fd)
  if not(file.flags.is_readable()) {
    raise IOError::PermissionDenied("File not opened for reading")
  }

  let data = self.fs.read_file(file.path) catch { e =>
    raise convert_memfs_error(e)
  }
  let start = file.offset.to_int()
  let end = @cmp.minimum(start + len, data.length())
  if start >= data.length() {
    return Bytes::new(0)
  }
  let result = data.sub(start~, end~).to_bytes()
  file.offset = end.to_int64()
  result
}

///|
pub impl Filesystem for MemfsBackend with write(self, fd, data) {
  let file = self.get_file(fd)
  if not(file.flags.is_writable()) {
    raise IOError::PermissionDenied("File not opened for writing")
  }

  let existing : Bytes = self.fs.read_file(file.path) catch { _ => Bytes::new(0) }
  let offset = file.offset.to_int()

  // Calculate new size
  let new_size = @cmp.maximum(offset + data.length(), existing.length())

  // Build new bytes
  let new_data = Bytes::makei(new_size, fn(i) {
    if i >= offset && i < offset + data.length() {
      // Write region: use new data
      data[i - offset]
    } else if i < existing.length() {
      // Existing data
      existing[i]
    } else {
      // Padding (shouldn't happen with correct logic)
      b'\x00'
    }
  })

  self.fs.write_file(file.path, new_data) catch { e =>
    raise convert_memfs_error(e)
  }
  file.offset = (offset + data.length()).to_int64()
  data.length()
}

///|
pub impl Filesystem for MemfsBackend with close(self, fd) {
  let file = self.get_file(fd)
  file.closed = true
  self.fd_table.remove(fd)
}

///|
pub impl Filesystem for MemfsBackend with stat(self, path) {
  let abs_path = self.resolve_path(path)
  if not(self.fs.exists(abs_path)) {
    raise IOError::NotFound(abs_path)
  }

  let file_type = if self.fs.is_dir(abs_path) {
    FileType::Directory
  } else {
    FileType::File
  }

  let size = self.fs.size(abs_path).unwrap_or(0).to_int64()

  { file_type, size, mode: FileMode::default(), mtime: 0L }
}

///|
pub impl Filesystem for MemfsBackend with exists(self, path) {
  let abs_path = self.resolve_path(path)
  self.fs.exists(abs_path)
}

///|
pub impl Filesystem for MemfsBackend with mkdir(self, path) {
  let abs_path = self.resolve_path(path)
  if self.fs.exists(abs_path) {
    raise IOError::AlreadyExists(abs_path)
  }
  self.fs.mkdir(abs_path) catch { e => raise convert_memfs_error(e) }
}

///|
pub impl Filesystem for MemfsBackend with readdir(self, path) {
  let abs_path = self.resolve_path(path)
  if not(self.fs.is_dir(abs_path)) {
    raise IOError::NotDirectory(abs_path)
  }

  let names = self.fs.readdir(abs_path) catch { e =>
    raise convert_memfs_error(e)
  }
  let entries : Array[DirEntry] = []
  for name in names {
    let full_path = if abs_path == "/" {
      "/" + name
    } else {
      abs_path + "/" + name
    }
    let file_type = if self.fs.is_dir(full_path) {
      FileType::Directory
    } else {
      FileType::File
    }
    entries.push({ name, file_type })
  }
  entries
}

///|
pub impl Filesystem for MemfsBackend with unlink(self, path) {
  let abs_path = self.resolve_path(path)
  if not(self.fs.exists(abs_path)) {
    raise IOError::NotFound(abs_path)
  }
  self.fs.remove(abs_path) catch { e => raise convert_memfs_error(e) }
}

///|
pub impl Filesystem for MemfsBackend with rename(self, from, to) {
  let abs_from = self.resolve_path(from)
  let abs_to = self.resolve_path(to)
  if not(self.fs.exists(abs_from)) {
    raise IOError::NotFound(abs_from)
  }

  // MemFS doesn't have rename, so we copy + delete
  if self.fs.is_dir(abs_from) {
    // For directories, just error for now (complex to implement recursively)
    raise IOError::Other("Renaming directories not yet supported")
  }

  let data = self.fs.read_file(abs_from) catch { e =>
    raise convert_memfs_error(e)
  }
  self.fs.write_file(abs_to, data) catch { e => raise convert_memfs_error(e) }
  self.fs.remove(abs_from) catch { e => raise convert_memfs_error(e) }
}

///|
pub impl Filesystem for MemfsBackend with realpath(self, path) {
  self.resolve_path(path)
}

// ============ ProcessManager implementation ============

///|
fn create_process_io(cmd : Command) -> ProcessIO {
  let stdin = match cmd.stdin {
    Stdio::Piped => Some(Pipe::new())
    _ => None
  }
  let stdout = match cmd.stdout {
    Stdio::Piped => Some(Pipe::new())
    _ => None
  }
  let stderr = match cmd.stderr {
    Stdio::Piped => Some(Pipe::new())
    _ => None
  }
  { stdin, stdout, stderr }
}

///|
pub impl ProcessManager for MemfsBackend with spawn(self, cmd) {
  match self.registry.get(cmd.program) {
    Some(handler) => {
      let pid = Pid(self.next_pid)
      self.next_pid += 1

      // Create I/O streams
      let io = create_process_io(cmd)

      // Create context for handler
      let ctx : ProcessContext = { backend: self, args: cmd.args, io }

      // Execute handler synchronously
      let exit_code = handler(ctx)

      let state : ProcessState = { pid, io, exit_code: Some(exit_code) }
      self.processes.set(pid, state)

      Process::{ pid }
    }
    None => raise ProcessError::NotFound(cmd.program)
  }
}

///|
pub impl ProcessManager for MemfsBackend with wait(self, pid) {
  match self.processes.get(pid) {
    Some(state) => {
      match state.exit_code {
        Some(code) => ExitStatus::{ code }
        None => {
          // Process still running - in real impl would block
          ExitStatus::{ code: 0 }
        }
      }
    }
    None => raise ProcessError::InvalidPid(pid)
  }
}

///|
pub impl ProcessManager for MemfsBackend with try_wait(self, pid) {
  match self.processes.get(pid) {
    Some(state) => {
      match state.exit_code {
        Some(code) => Some(ExitStatus::{ code })
        None => None
      }
    }
    None => raise ProcessError::InvalidPid(pid)
  }
}

///|
pub impl ProcessManager for MemfsBackend with kill(self, pid, _signal) {
  match self.processes.get(pid) {
    Some(state) => {
      if state.exit_code is Some(_) {
        raise ProcessError::AlreadyExited(pid)
      }
      state.exit_code = Some(128 + 9) // Killed
    }
    None => raise ProcessError::InvalidPid(pid)
  }
}

///|
pub impl ProcessManager for MemfsBackend with current_pid(self) {
  self.current_pid
}

///|
pub impl ProcessManager for MemfsBackend with read_stdout(self, pid) {
  match self.processes.get(pid) {
    Some(state) =>
      match state.io.stdout {
        Some(pipe) => pipe.read_string()
        None => ""
      }
    None => raise ProcessError::InvalidPid(pid)
  }
}

///|
pub impl ProcessManager for MemfsBackend with read_stderr(self, pid) {
  match self.processes.get(pid) {
    Some(state) =>
      match state.io.stderr {
        Some(pipe) => pipe.read_string()
        None => ""
      }
    None => raise ProcessError::InvalidPid(pid)
  }
}

///|
pub impl ProcessManager for MemfsBackend with write_stdin(self, pid, data) {
  match self.processes.get(pid) {
    Some(state) =>
      match state.io.stdin {
        Some(pipe) => {
          let _ = pipe.write_string(data)

        }
        None => ()
      }
    None => raise ProcessError::InvalidPid(pid)
  }
}

// ============ Network implementation (stub) ============

///|
pub impl Network for MemfsBackend with tcp_connect(self, addr) {
  raise NetworkError::Other("Network not supported in memfs mode: \{addr}")
}

///|
pub impl Network for MemfsBackend with tcp_read(self, _conn, _len) {
  raise NetworkError::Other("Network not supported in memfs mode")
}

///|
pub impl Network for MemfsBackend with tcp_write(self, _conn, _data) {
  raise NetworkError::Other("Network not supported in memfs mode")
}

///|
pub impl Network for MemfsBackend with tcp_close(self, _conn) {
  // No-op
}

///|
pub impl Network for MemfsBackend with tcp_listen(self, addr) {
  raise NetworkError::Other("Network not supported in memfs mode: \{addr}")
}

///|
pub impl Network for MemfsBackend with tcp_accept(self, _listener) {
  raise NetworkError::Other("Network not supported in memfs mode")
}

///|
pub impl Network for MemfsBackend with tcp_listener_close(self, _listener) {
  // No-op
}

///|
pub impl Network for MemfsBackend with resolve(self, host) {
  raise NetworkError::HostNotFound(host)
}

// ============ Environment implementation ============

///|
pub impl Environment for MemfsBackend with get_env(self, name) {
  self.env.get(name)
}

///|
pub impl Environment for MemfsBackend with set_env(self, name, value) {
  self.env.set(name, value)
}

///|
pub impl Environment for MemfsBackend with env_vars(self) {
  self.env
}

///|
pub impl Environment for MemfsBackend with args(self) {
  self.args
}

///|
pub impl Environment for MemfsBackend with cwd(self) {
  self.cwd
}

///|
pub impl Environment for MemfsBackend with chdir(self, path) {
  let abs_path = self.resolve_path(path)
  if not(self.fs.is_dir(abs_path)) {
    raise IOError::NotDirectory(abs_path)
  }
  self.cwd = abs_path
  self.env.set("PWD", abs_path)
}
