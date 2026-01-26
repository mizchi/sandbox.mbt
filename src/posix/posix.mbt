/// POSIX Context - fd管理、プロセス管理、時間管理を提供

/// POSIX error with errno
pub(all) suberror PosixError {
  PosixErrno(Errno, String)  // errno + message
}

pub fn PosixError::errno(self : PosixError) -> Errno {
  match self {
    PosixErrno(e, _) => e
  }
}

// ============ Open File Description ============

/// Internal state of an open file
struct OpenFile {
  path : String
  mut flags : OpenFlags
  mode : FileMode
  mut offset : Int64
  mut closed : Bool
  // For pipes
  is_pipe : Bool
  pipe_buffer : Array[Byte]?
  pipe_read_end : Bool  // true if this is the read end
}

fn OpenFile::new(
  path : String,
  flags : OpenFlags,
  mode : FileMode
) -> OpenFile {
  {
    path,
    flags,
    mode,
    offset: 0L,
    closed: false,
    is_pipe: false,
    pipe_buffer: None,
    pipe_read_end: false,
  }
}

fn OpenFile::new_pipe(buffer : Array[Byte], is_read_end : Bool) -> OpenFile {
  {
    path: "<pipe>",
    flags: if is_read_end { OpenFlags::from([O_RDONLY]) } else { OpenFlags::from([O_WRONLY]) },
    mode: FileMode::new(0o600),
    offset: 0L,
    closed: false,
    is_pipe: true,
    pipe_buffer: Some(buffer),
    pipe_read_end: is_read_end,
  }
}

// ============ Process State ============

/// Internal process state
struct Process {
  pid : Pid
  ppid : Pid
  command : String
  args : Array[String]
  env : Map[String, String]
  cwd : String
  mut exit_code : Int?
}

fn Process::new(
  pid : Pid,
  ppid : Pid,
  command : String,
  args : Array[String],
  env : Map[String, String],
  cwd : String
) -> Process {
  { pid, ppid, command, args, env, cwd, exit_code: None }
}

fn Process::is_running(self : Process) -> Bool {
  self.exit_code is None
}

// ============ POSIX Context ============

/// POSIX runtime context
pub struct PosixContext {
  // File descriptor table
  fd_table : Map[Fd, OpenFile]
  mut next_fd : Int

  // Filesystem backend
  fs : @fs.MemFS

  // Process table
  processes : Map[Pid, Process]
  mut next_pid : Int
  current_pid : Pid

  // Environment
  env : Map[String, String]
  mut cwd : String

  // Time (for sandbox mode - can be mocked)
  mut mock_time : Int64?  // If Some, use this instead of real time
  monotonic_base : Int64

  // User/Group (sandbox defaults)
  uid : Int
  gid : Int
  euid : Int
  egid : Int
}

pub fn PosixContext::new(fs : @fs.MemFS) -> PosixContext {
  let ctx : PosixContext = {
    fd_table: {},
    next_fd: 3,  // 0, 1, 2 are reserved
    fs,
    processes: {},
    next_pid: 2,
    current_pid: Pid(1),
    env: {},
    cwd: "/",
    mock_time: None,
    monotonic_base: 0L,
    uid: 1000,
    gid: 1000,
    euid: 1000,
    egid: 1000,
  }

  // Set up standard file descriptors
  ctx.fd_table.set(Fd(0), OpenFile::new("<stdin>", OpenFlags::from([O_RDONLY]), FileMode::new(0o600)))
  ctx.fd_table.set(Fd(1), OpenFile::new("<stdout>", OpenFlags::from([O_WRONLY]), FileMode::new(0o600)))
  ctx.fd_table.set(Fd(2), OpenFile::new("<stderr>", OpenFlags::from([O_WRONLY]), FileMode::new(0o600)))

  // Set default environment
  ctx.env.set("HOME", "/home")
  ctx.env.set("PATH", "/bin:/usr/bin")
  ctx.env.set("USER", "user")
  ctx.env.set("SHELL", "/bin/sh")
  ctx.env.set("PWD", "/")

  // Create initial process
  ctx.processes.set(Pid(1), Process::new(
    Pid(1), Pid(0), "/bin/init", [], ctx.env, "/"
  ))

  ctx
}

pub fn PosixContext::default() -> PosixContext {
  PosixContext::new(@fs.MemFS::default())
}

// ============ File Descriptor Operations ============

/// Allocate a new file descriptor
fn PosixContext::alloc_fd(self : PosixContext) -> Fd {
  let fd = Fd(self.next_fd)
  self.next_fd += 1
  fd
}

/// Get open file by fd
fn PosixContext::get_file(self : PosixContext, fd : Fd) -> OpenFile raise PosixError {
  match self.fd_table.get(fd) {
    Some(f) => {
      if f.closed {
        raise PosixErrno(EBADF, "File descriptor closed")
      }
      f
    }
    None => raise PosixErrno(EBADF, "Bad file descriptor")
  }
}

/// Open a file
pub fn PosixContext::open(
  self : PosixContext,
  path : String,
  flags : OpenFlags,
  mode : FileMode
) -> Fd raise PosixError {
  let abs_path = self.resolve_path(path)

  let exists = self.fs.exists(abs_path)

  // Handle O_CREAT
  if flags.has(O_CREAT) {
    if exists && flags.has(O_EXCL) {
      raise PosixErrno(EEXIST, "File exists")
    }
    if not(exists) {
      try {
        self.fs.write_string(abs_path, "")
      } catch {
        e => raise PosixErrno(EIO, e.to_string())
      }
    }
  } else if not(exists) {
    raise PosixErrno(ENOENT, "No such file or directory")
  }

  // Check if directory
  if self.fs.is_dir(abs_path) {
    if flags.is_writable() {
      raise PosixErrno(EISDIR, "Is a directory")
    }
    if not(flags.has(O_DIRECTORY)) && flags.is_readable() {
      raise PosixErrno(EISDIR, "Is a directory")
    }
  }

  // Handle O_TRUNC
  if flags.has(O_TRUNC) && flags.is_writable() && not(self.fs.is_dir(abs_path)) {
    try {
      self.fs.write_string(abs_path, "")
    } catch {
      e => raise PosixErrno(EIO, e.to_string())
    }
  }

  let fd = self.alloc_fd()
  let file = OpenFile::new(abs_path, flags, mode)

  // Handle O_APPEND
  if flags.has(O_APPEND) {
    match self.fs.size(abs_path) {
      Some(size) => file.offset = size.to_int64()
      None => ()
    }
  }

  self.fd_table.set(fd, file)
  fd
}

/// Close a file descriptor
pub fn PosixContext::close(self : PosixContext, fd : Fd) -> Unit raise PosixError {
  let file = self.get_file(fd)
  file.closed = true
  self.fd_table.remove(fd)
}

/// Read from a file descriptor
pub fn PosixContext::read(
  self : PosixContext,
  fd : Fd,
  count : Int
) -> Bytes raise PosixError {
  let file = self.get_file(fd)

  if not(file.flags.is_readable()) {
    raise PosixErrno(EBADF, "File not open for reading")
  }

  // Handle pipe
  if file.is_pipe {
    match file.pipe_buffer {
      Some(buf) => {
        let available = buf.length() - file.offset.to_int()
        let to_read = if count < available { count } else { available }
        if to_read <= 0 {
          return Bytes::new(0)
        }
        let arr : Array[Byte] = []
        for i in 0..<to_read {
          arr.push(buf[file.offset.to_int() + i])
        }
        file.offset += to_read.to_int64()
        return Bytes::from_array(arr)
      }
      None => return Bytes::new(0)
    }
  }

  // Handle special files
  if file.path == "<stdin>" || file.path == "<stdout>" || file.path == "<stderr>" {
    return Bytes::new(0)  // No actual I/O in sandbox mode
  }

  // Read from filesystem
  try {
    let content = self.fs.read_file(file.path)
    let start = file.offset.to_int()
    let available = content.length() - start
    let to_read = if count < available { count } else { available }

    if to_read <= 0 {
      return Bytes::new(0)
    }

    let arr : Array[Byte] = []
    for i in 0..<to_read {
      arr.push(content[start + i])
    }
    file.offset += to_read.to_int64()
    Bytes::from_array(arr)
  } catch {
    e => raise PosixErrno(EIO, e.to_string())
  }
}

/// Write to a file descriptor
pub fn PosixContext::write(
  self : PosixContext,
  fd : Fd,
  data : Bytes
) -> Int raise PosixError {
  let file = self.get_file(fd)

  if not(file.flags.is_writable()) {
    raise PosixErrno(EBADF, "File not open for writing")
  }

  // Handle pipe
  if file.is_pipe {
    match file.pipe_buffer {
      Some(buf) => {
        for b in data {
          buf.push(b)
        }
        return data.length()
      }
      None => raise PosixErrno(EPIPE, "Broken pipe")
    }
  }

  // Handle special files (just count bytes in sandbox)
  if file.path == "<stdin>" || file.path == "<stdout>" || file.path == "<stderr>" {
    return data.length()
  }

  // Write to filesystem
  try {
    let current = try { self.fs.read_file(file.path) } catch { _ => Bytes::new(0) }

    let offset = file.offset.to_int()
    let arr : Array[Byte] = []

    // Copy existing content up to offset
    for i in 0..<offset {
      if i < current.length() {
        arr.push(current[i])
      } else {
        arr.push(b'\x00')
      }
    }

    // Write new data
    for b in data {
      arr.push(b)
    }

    self.fs.write_file(file.path, Bytes::from_array(arr))
    file.offset += data.length().to_int64()
    data.length()
  } catch {
    e => raise PosixErrno(EIO, e.to_string())
  }
}

/// Seek in a file
pub fn PosixContext::lseek(
  self : PosixContext,
  fd : Fd,
  offset : Int64,
  whence : Whence
) -> Int64 raise PosixError {
  let file = self.get_file(fd)

  if file.is_pipe {
    raise PosixErrno(ESPIPE, "Illegal seek on pipe")
  }

  let size = self.fs.size(file.path).unwrap_or(0).to_int64()

  let new_offset = match whence {
    SEEK_SET => offset
    SEEK_CUR => file.offset + offset
    SEEK_END => size + offset
  }

  if new_offset < 0L {
    raise PosixErrno(EINVAL, "Invalid seek offset")
  }

  file.offset = new_offset
  new_offset
}

/// Duplicate a file descriptor
pub fn PosixContext::dup(self : PosixContext, old_fd : Fd) -> Fd raise PosixError {
  let file = self.get_file(old_fd)
  let new_fd = self.alloc_fd()

  let new_file = OpenFile::new(file.path, file.flags, file.mode)
  new_file.offset = file.offset

  self.fd_table.set(new_fd, new_file)
  new_fd
}

/// Duplicate a file descriptor to a specific number
pub fn PosixContext::dup2(
  self : PosixContext,
  old_fd : Fd,
  new_fd : Fd
) -> Fd raise PosixError {
  if old_fd == new_fd {
    let _ = self.get_file(old_fd)
    return new_fd
  }

  // Close new_fd if open
  if self.fd_table.contains(new_fd) {
    try { self.close(new_fd) } catch { _ => () }
  }

  let file = self.get_file(old_fd)

  let new_file = OpenFile::new(file.path, file.flags, file.mode)
  new_file.offset = file.offset

  self.fd_table.set(new_fd, new_file)
  new_fd
}

/// Create a pipe
pub fn PosixContext::pipe(self : PosixContext) -> PipeFds {
  let buffer : Array[Byte] = []

  let read_fd = self.alloc_fd()
  let write_fd = self.alloc_fd()

  self.fd_table.set(read_fd, OpenFile::new_pipe(buffer, true))
  self.fd_table.set(write_fd, OpenFile::new_pipe(buffer, false))

  { read_fd, write_fd }
}

// ============ Stat Operations ============

/// Get current time (mock or real)
pub fn PosixContext::get_time(self : PosixContext) -> Int64 {
  match self.mock_time {
    Some(t) => t
    None => 0L  // In real impl, would use actual time
  }
}

/// Set mock time for testing
pub fn PosixContext::set_mock_time(self : PosixContext, time : Int64) -> Unit {
  self.mock_time = Some(time)
}

/// Get file status (follows symlinks)
pub fn PosixContext::stat(self : PosixContext, path : String) -> Stat raise PosixError {
  let abs_path = self.resolve_path(path)

  if not(self.fs.exists(abs_path)) {
    raise PosixErrno(ENOENT, "No such file or directory")
  }

  // Follow symlinks for stat()
  let resolved = try {
    self.fs.resolve_path(abs_path)
  } catch {
    _ => abs_path
  }

  if not(self.fs.exists(resolved)) {
    raise PosixErrno(ENOENT, "No such file or directory")
  }

  let now = self.get_time()

  if self.fs.is_dir(resolved) {
    Stat::new_dir(FileMode::default_dir(), now)
  } else {
    let size = self.fs.size(resolved).unwrap_or(0)
    Stat::new_file(size.to_int64(), FileMode::default_file(), now)
  }
}

/// Get file status by fd
pub fn PosixContext::fstat(self : PosixContext, fd : Fd) -> Stat raise PosixError {
  let file = self.get_file(fd)

  // Handle pipes
  if file.is_pipe {
    return {
      st_dev: 0,
      st_ino: 0,
      st_mode: FileMode::new(0o600),
      st_nlink: 1,
      st_uid: self.uid,
      st_gid: self.gid,
      st_rdev: 0,
      st_size: 0L,
      st_blksize: 4096,
      st_blocks: 0L,
      st_atime: 0L,
      st_mtime: 0L,
      st_ctime: 0L,
      st_type: S_IFIFO,
    }
  }

  // Handle special file descriptors (stdin/stdout/stderr)
  if file.path == "<stdin>" || file.path == "<stdout>" || file.path == "<stderr>" {
    return {
      st_dev: 0,
      st_ino: 0,
      st_mode: file.mode,
      st_nlink: 1,
      st_uid: self.uid,
      st_gid: self.gid,
      st_rdev: 0,
      st_size: 0L,
      st_blksize: 4096,
      st_blocks: 0L,
      st_atime: 0L,
      st_mtime: 0L,
      st_ctime: 0L,
      st_type: S_IFCHR,  // Character device
    }
  }

  self.stat(file.path)
}

/// Get symlink status (don't follow symlink)
pub fn PosixContext::lstat(self : PosixContext, path : String) -> Stat raise PosixError {
  let abs_path = self.resolve_path(path)

  if not(self.fs.exists(abs_path)) {
    raise PosixErrno(ENOENT, "No such file or directory")
  }

  let now = self.get_time()

  if self.fs.is_symlink(abs_path) {
    let target = try { self.fs.read_link(abs_path) } catch { _ => "" }
    return Stat::new_symlink(target.length(), now)
  }

  self.stat(path)
}

// ============ Path Operations ============

/// Resolve relative path to absolute
pub fn PosixContext::resolve_path(self : PosixContext, path : String) -> String {
  if path.has_prefix("/") {
    normalize_posix_path(path)
  } else if path == "~" || path.has_prefix("~/") {
    let home = self.env.get("HOME").unwrap_or("/home")
    if path == "~" {
      home
    } else {
      let rest = posix_substring_from(path, 2)
      normalize_posix_path(home + "/" + rest)
    }
  } else {
    normalize_posix_path(self.cwd + "/" + path)
  }
}

fn normalize_posix_path(path : String) -> String {
  let parts = posix_split_path(path)
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

fn posix_split_path(path : String) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()

  for c in path {
    if c == '/' {
      if current.to_string().length() > 0 {
        result.push(current.to_string())
        current.reset()
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

fn posix_substring_from(s : String, start : Int) -> String {
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

// ============ Environment ============

pub fn PosixContext::getenv(self : PosixContext, name : String) -> String? {
  self.env.get(name)
}

pub fn PosixContext::setenv(self : PosixContext, name : String, value : String) -> Unit {
  self.env.set(name, value)
  if name == "PWD" {
    self.cwd = value
  }
}

pub fn PosixContext::unsetenv(self : PosixContext, name : String) -> Unit {
  self.env.remove(name)
}

pub fn PosixContext::getcwd(self : PosixContext) -> String {
  self.cwd
}

pub fn PosixContext::chdir(self : PosixContext, path : String) -> Unit raise PosixError {
  let abs_path = self.resolve_path(path)

  if not(self.fs.exists(abs_path)) {
    raise PosixErrno(ENOENT, "No such file or directory")
  }

  if not(self.fs.is_dir(abs_path)) {
    raise PosixErrno(ENOTDIR, "Not a directory")
  }

  self.cwd = abs_path
  self.env.set("PWD", abs_path)
}

// ============ User/Group ============

pub fn PosixContext::getuid(self : PosixContext) -> Int {
  self.uid
}

pub fn PosixContext::geteuid(self : PosixContext) -> Int {
  self.euid
}

pub fn PosixContext::getgid(self : PosixContext) -> Int {
  self.gid
}

pub fn PosixContext::getegid(self : PosixContext) -> Int {
  self.egid
}

pub fn PosixContext::getpid(self : PosixContext) -> Pid {
  self.current_pid
}

// ============ Process Operations ============

/// Spawn a new process (in sandbox mode, just creates a process entry)
pub fn PosixContext::spawn(
  self : PosixContext,
  command : String,
  args : Array[String]
) -> Pid {
  let pid = Pid(self.next_pid)
  self.next_pid += 1

  let process = Process::new(
    pid,
    self.current_pid,
    command,
    args,
    self.env,
    self.cwd
  )
  self.processes.set(pid, process)
  pid
}

/// Check if process is running
pub fn PosixContext::process_running(self : PosixContext, pid : Pid) -> Bool {
  match self.processes.get(pid) {
    Some(p) => p.is_running()
    None => false
  }
}

/// Set process exit code (simulates process completion)
pub fn PosixContext::process_exit(self : PosixContext, pid : Pid, code : Int) -> Unit {
  match self.processes.get(pid) {
    Some(p) => p.exit_code = Some(code)
    None => ()
  }
}

/// Wait for process (in sandbox, just returns exit code if set)
pub fn PosixContext::waitpid(self : PosixContext, pid : Pid) -> Int? {
  match self.processes.get(pid) {
    Some(p) => p.exit_code
    None => None
  }
}

// ============ Time Operations ============

/// Get current time
pub fn PosixContext::clock_gettime(self : PosixContext, clock_id : ClockId) -> Timespec {
  let time = match clock_id {
    CLOCK_REALTIME => self.get_time()
    CLOCK_MONOTONIC => self.get_time() - self.monotonic_base
    CLOCK_PROCESS_CPUTIME_ID => 0L
    CLOCK_THREAD_CPUTIME_ID => 0L
  }
  Timespec::from_millis(time)
}

/// Get real time
pub fn PosixContext::time(self : PosixContext) -> Int64 {
  self.get_time() / 1000L  // Convert ms to seconds
}

// ============ Filesystem ============

/// Get underlying filesystem
pub fn PosixContext::get_fs(self : PosixContext) -> @fs.MemFS {
  self.fs
}

// ============ fcntl Operations ============

/// Get file descriptor flags
pub fn PosixContext::fcntl_getfl(self : PosixContext, fd : Fd) -> OpenFlags raise PosixError {
  let file = self.get_file(fd)
  file.flags
}

/// Set file descriptor flags
pub fn PosixContext::fcntl_setfl(
  self : PosixContext,
  fd : Fd,
  flags : OpenFlags
) -> Unit raise PosixError {
  let file = self.get_file(fd)
  // Only certain flags can be modified: O_APPEND, O_NONBLOCK, O_SYNC
  // Access mode (O_RDONLY, O_WRONLY, O_RDWR) cannot be changed
  if flags.has(O_NONBLOCK) {
    file.flags = file.flags.add(O_NONBLOCK)
  }
  if flags.has(O_APPEND) {
    file.flags = file.flags.add(O_APPEND)
  }
  if flags.has(O_SYNC) {
    file.flags = file.flags.add(O_SYNC)
  }
}

/// Duplicate fd to a number >= min_fd
pub fn PosixContext::fcntl_dupfd(
  self : PosixContext,
  fd : Fd,
  min_fd : Int
) -> Fd raise PosixError {
  let file = self.get_file(fd)

  // Find first available fd >= min_fd
  let mut new_fd_num = min_fd
  while self.fd_table.contains(Fd(new_fd_num)) {
    new_fd_num += 1
  }

  let new_fd = Fd(new_fd_num)
  let new_file = OpenFile::new(file.path, file.flags, file.mode)
  new_file.offset = file.offset

  self.fd_table.set(new_fd, new_file)

  // Update next_fd if necessary
  if new_fd_num >= self.next_fd {
    self.next_fd = new_fd_num + 1
  }

  new_fd
}

// ============ poll Operation ============

/// Poll multiple file descriptors for I/O readiness
/// Returns the number of ready file descriptors
pub fn PosixContext::poll(
  self : PosixContext,
  pollfds : Array[PollFd],
  _timeout_ms : Int  // timeout in milliseconds (-1 = block, 0 = immediate)
) -> Int {
  let mut ready_count = 0

  for pfd in pollfds {
    pfd.clear_revents()

    let fd = pfd.get_fd()

    // Check if fd is valid
    match self.fd_table.get(fd) {
      None => {
        pfd.set_revent(POLLNVAL)
        ready_count += 1
        continue
      }
      Some(file) => {
        if file.closed {
          pfd.set_revent(POLLNVAL)
          ready_count += 1
          continue
        }

        let mut is_ready = false

        // Check POLLIN (readable)
        if pfd.has_event(POLLIN) {
          if self.is_readable(fd, file) {
            pfd.set_revent(POLLIN)
            is_ready = true
          }
        }

        // Check POLLOUT (writable)
        if pfd.has_event(POLLOUT) {
          if self.is_writable(fd, file) {
            pfd.set_revent(POLLOUT)
            is_ready = true
          }
        }

        if is_ready {
          ready_count += 1
        }
      }
    }
  }

  ready_count
}

/// Check if fd is readable (has data or is regular file)
fn PosixContext::is_readable(self : PosixContext, _fd : Fd, file : OpenFile) -> Bool {
  if not(file.flags.is_readable()) {
    return false
  }

  // Pipes: check if data is available
  if file.is_pipe {
    match file.pipe_buffer {
      Some(buf) => {
        let available = buf.length() - file.offset.to_int()
        return available > 0
      }
      None => return false
    }
  }

  // Regular files are always "ready" for reading
  // (though they may be at EOF)
  true
}

/// Check if fd is writable
fn PosixContext::is_writable(self : PosixContext, _fd : Fd, file : OpenFile) -> Bool {
  if not(file.flags.is_writable()) {
    return false
  }

  // Pipes: always writable (in this simple implementation)
  if file.is_pipe {
    return true
  }

  // Regular files are always ready for writing
  true
}

// ============ access Operation ============

/// Check file accessibility
pub fn PosixContext::access(
  self : PosixContext,
  path : String,
  mode : AccessMode
) -> Unit raise PosixError {
  let abs_path = self.resolve_path(path)

  // Check existence first
  if not(self.fs.exists(abs_path)) {
    raise PosixErrno(ENOENT, "No such file or directory")
  }

  // F_OK just checks existence
  if mode == F_OK {
    return
  }

  // For sandbox, we assume user has all permissions on their files
  // In a real implementation, we'd check st_mode against uid/gid
  match mode {
    R_OK => ()  // Always readable in sandbox
    W_OK => ()  // Always writable in sandbox
    X_OK => {
      // Directories are always executable (searchable)
      // Files need execute bit (we assume true in sandbox)
      ()
    }
    F_OK => ()  // Already handled above
  }
}

// ============ rename Operation ============

/// Rename (move) a file or directory
pub fn PosixContext::rename(
  self : PosixContext,
  old_path : String,
  new_path : String
) -> Unit raise PosixError {
  let abs_old = self.resolve_path(old_path)
  let abs_new = self.resolve_path(new_path)

  try {
    self.fs.rename(abs_old, abs_new)
  } catch {
    NotFound(p) => raise PosixErrno(ENOENT, "No such file or directory: " + p)
    NotADirectory(p) => raise PosixErrno(ENOTDIR, "Not a directory: " + p)
    AlreadyExists(_) => raise PosixErrno(EEXIST, "File exists")
    e => raise PosixErrno(EIO, e.to_string())
  }
}

// ============ truncate Operations ============

/// Truncate a file to specified length
pub fn PosixContext::truncate(
  self : PosixContext,
  path : String,
  length : Int64
) -> Unit raise PosixError {
  let abs_path = self.resolve_path(path)
  // Let @fs.MemFS::truncate handle existence/type checks to avoid duplicate lookups
  try {
    self.fs.truncate(abs_path, length.to_int())
  } catch {
    NotFound(p) => raise PosixErrno(ENOENT, "No such file or directory: " + p)
    NotAFile(_) => raise PosixErrno(EISDIR, "Is a directory")
    e => raise PosixErrno(EIO, e.to_string())
  }
}

/// Truncate a file to specified length by fd
pub fn PosixContext::ftruncate(
  self : PosixContext,
  fd : Fd,
  length : Int64
) -> Unit raise PosixError {
  let file = self.get_file(fd)

  if not(file.flags.is_writable()) {
    raise PosixErrno(EBADF, "File not open for writing")
  }

  if file.is_pipe {
    raise PosixErrno(EINVAL, "Invalid argument")
  }

  try {
    self.fs.truncate(file.path, length.to_int())
  } catch {
    e => raise PosixErrno(EIO, e.to_string())
  }

  // Adjust offset if beyond new length
  if file.offset > length {
    file.offset = length
  }
}

/// Create a directory
pub fn PosixContext::mkdir(
  self : PosixContext,
  path : String,
  mode : FileMode
) -> Unit raise PosixError {
  let abs_path = self.resolve_path(path)
  try {
    self.fs.mkdir(abs_path)
  } catch {
    AlreadyExists(_) => raise PosixErrno(EEXIST, "File exists")
    NotADirectory(p) => raise PosixErrno(ENOENT, "No such file or directory: " + p)
    e => raise PosixErrno(EIO, e.to_string())
  }
  // Note: mode is currently ignored as MemFS doesn't track permissions
  ignore(mode)
}

/// Remove an empty directory
pub fn PosixContext::rmdir(self : PosixContext, path : String) -> Unit raise PosixError {
  let abs_path = self.resolve_path(path)
  if not(self.fs.exists(abs_path)) {
    raise PosixErrno(ENOENT, "No such file or directory")
  }
  if not(self.fs.is_dir(abs_path)) {
    raise PosixErrno(ENOTDIR, "Not a directory")
  }
  try {
    self.fs.rmdir(abs_path)
  } catch {
    NotADirectory(msg) => {
      if msg.contains("not empty") {
        raise PosixErrno(ENOTEMPTY, "Directory not empty")
      }
      raise PosixErrno(ENOTDIR, msg)
    }
    InvalidPath(_) => raise PosixErrno(EINVAL, "Invalid argument")
    e => raise PosixErrno(EIO, e.to_string())
  }
}

/// Remove a file or symbolic link
pub fn PosixContext::unlink(self : PosixContext, path : String) -> Unit raise PosixError {
  let abs_path = self.resolve_path(path)
  if not(self.fs.exists(abs_path)) {
    raise PosixErrno(ENOENT, "No such file or directory")
  }
  if self.fs.is_dir(abs_path) {
    raise PosixErrno(EISDIR, "Is a directory")
  }
  try {
    self.fs.remove(abs_path)
  } catch {
    e => raise PosixErrno(EIO, e.to_string())
  }
}

/// Create a symbolic link
pub fn PosixContext::symlink(
  self : PosixContext,
  link_path : String,
  target : String
) -> Unit raise PosixError {
  let abs_link = self.resolve_path(link_path)
  if self.fs.exists(abs_link) {
    raise PosixErrno(EEXIST, "File exists")
  }
  try {
    self.fs.symlink(abs_link, target)
  } catch {
    NotADirectory(p) => raise PosixErrno(ENOENT, "No such file or directory: " + p)
    e => raise PosixErrno(EIO, e.to_string())
  }
}

/// Read the target of a symbolic link
pub fn PosixContext::readlink(self : PosixContext, path : String) -> String raise PosixError {
  let abs_path = self.resolve_path(path)
  if not(self.fs.exists(abs_path)) {
    raise PosixErrno(ENOENT, "No such file or directory")
  }
  if not(self.fs.is_symlink(abs_path)) {
    raise PosixErrno(EINVAL, "Invalid argument")
  }
  try {
    self.fs.read_link(abs_path)
  } catch {
    e => raise PosixErrno(EIO, e.to_string())
  }
}
