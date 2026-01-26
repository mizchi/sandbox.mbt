/// Runtime traits - abstract interfaces for different backends

///|
/// Filesystem operations
pub(open) trait Filesystem {
  // File operations
  open(Self, String, OpenFlags) -> Fd raise IOError
  read(Self, Fd, Int) -> Bytes raise IOError
  write(Self, Fd, Bytes) -> Int raise IOError
  close(Self, Fd) -> Unit raise IOError

  // File info
  stat(Self, String) -> FileStat raise IOError
  exists(Self, String) -> Bool

  // Directory operations
  mkdir(Self, String) -> Unit raise IOError
  readdir(Self, String) -> Array[DirEntry] raise IOError

  // File management
  unlink(Self, String) -> Unit raise IOError
  rename(Self, String, String) -> Unit raise IOError

  // Path operations
  realpath(Self, String) -> String raise IOError
}

///|
/// Process handle returned by spawn
pub(all) struct Process {
  pid : Pid
  // stdin/stdout/stderr pipes would be here if Piped
}

///|
pub fn Process::pid(self : Process) -> Pid {
  self.pid
}

///|
/// Process management
pub(open) trait ProcessManager {
  spawn(Self, Command) -> Process raise ProcessError
  wait(Self, Pid) -> ExitStatus raise ProcessError
  try_wait(Self, Pid) -> ExitStatus? raise ProcessError
  kill(Self, Pid, Signal) -> Unit raise ProcessError
  current_pid(Self) -> Pid
  // I/O
  read_stdout(Self, Pid) -> String raise ProcessError
  read_stderr(Self, Pid) -> String raise ProcessError
  write_stdin(Self, Pid, String) -> Unit raise ProcessError
}

///|
/// TCP stream abstraction
pub(all) struct TcpConn {
  id : Int // Internal connection ID
}

///|
/// TCP listener abstraction
pub(all) struct TcpListenerHandle {
  id : Int
}

///|
/// Network operations
pub(open) trait Network {
  tcp_connect(Self, SocketAddr) -> TcpConn raise NetworkError
  tcp_read(Self, TcpConn, Int) -> Bytes raise NetworkError
  tcp_write(Self, TcpConn, Bytes) -> Int raise NetworkError
  tcp_close(Self, TcpConn) -> Unit
  tcp_listen(Self, SocketAddr) -> TcpListenerHandle raise NetworkError
  tcp_accept(Self, TcpListenerHandle) -> TcpConn raise NetworkError
  tcp_listener_close(Self, TcpListenerHandle) -> Unit
  resolve(Self, String) -> Array[String] raise NetworkError
}

///|
/// Environment operations
pub(open) trait Environment {
  get_env(Self, String) -> String?
  set_env(Self, String, String) -> Unit
  env_vars(Self) -> Map[String, String]
  args(Self) -> Array[String]
  cwd(Self) -> String
  chdir(Self, String) -> Unit raise IOError
}
