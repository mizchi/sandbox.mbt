/// Runtime common types

/// File descriptor
pub(all) struct Fd(Int) derive(Eq, Hash, Show)

/// Process ID
pub(all) struct Pid(Int) derive(Eq, Hash, Show)

/// Signal number
pub(all) struct Signal(Int) derive(Eq, Show)

/// Common signals
pub fn sigterm() -> Signal {
  Signal(15)
}

///|
pub fn sigkill() -> Signal {
  Signal(9)
}

///|
pub fn sigint() -> Signal {
  Signal(2)
}

/// Open flags
pub(all) struct OpenFlags {
  read : Bool
  write : Bool
  append : Bool
  create : Bool
  truncate : Bool
  exclusive : Bool
}

///|
pub fn OpenFlags::read_only() -> OpenFlags {
  { read: true, write: false, append: false, create: false, truncate: false, exclusive: false }
}

///|
pub fn OpenFlags::write_only() -> OpenFlags {
  { read: false, write: true, append: false, create: false, truncate: false, exclusive: false }
}

///|
pub fn OpenFlags::read_write() -> OpenFlags {
  { read: true, write: true, append: false, create: false, truncate: false, exclusive: false }
}

///|
pub fn OpenFlags::create() -> OpenFlags {
  { read: true, write: true, append: false, create: true, truncate: false, exclusive: false }
}

///|
pub fn OpenFlags::is_readable(self : OpenFlags) -> Bool {
  self.read
}

///|
pub fn OpenFlags::is_writable(self : OpenFlags) -> Bool {
  self.write
}

/// File mode (permissions)
pub(all) struct FileMode(Int) derive(Eq, Show)

///|
pub fn FileMode::default() -> FileMode {
  FileMode(0o644)
}

/// File type
pub(all) enum FileType {
  File
  Directory
  Symlink
  Other
}

/// File stat information
pub(all) struct FileStat {
  file_type : FileType
  size : Int64
  mode : FileMode
  mtime : Int64
}

/// Directory entry
pub(all) struct DirEntry {
  name : String
  file_type : FileType
}

/// Socket address
pub(all) struct SocketAddr {
  host : String
  port : Int
}

///|
pub fn SocketAddr::new(host : String, port : Int) -> SocketAddr {
  { host, port }
}

///|
pub impl Show for SocketAddr with output(self, logger) {
  logger.write_string("\{self.host}:\{self.port}")
}

/// Exit status
pub(all) struct ExitStatus {
  code : Int
}

///|
pub fn ExitStatus::success() -> ExitStatus {
  { code: 0 }
}

///|
pub fn ExitStatus::is_success(self : ExitStatus) -> Bool {
  self.code == 0
}

/// Command to execute
pub(all) struct Command {
  program : String
  args : Array[String]
  env : Map[String, String]
  cwd : String?
  stdin : Stdio
  stdout : Stdio
  stderr : Stdio
}

/// Stdio configuration
pub(all) enum Stdio {
  Inherit
  Null
  Piped
}

///|
pub fn Command::new(program : String) -> Command {
  {
    program,
    args: [],
    env: {},
    cwd: None,
    stdin: Stdio::Inherit,
    stdout: Stdio::Inherit,
    stderr: Stdio::Inherit,
  }
}

///|
pub fn Command::arg(self : Command, arg : String) -> Command {
  let args = self.args.copy()
  args.push(arg)
  { ..self, args }
}

///|
pub fn Command::args(self : Command, args : Array[String]) -> Command {
  let new_args = self.args.copy()
  for a in args {
    new_args.push(a)
  }
  { ..self, args: new_args }
}

///|
pub fn Command::env(self : Command, key : String, value : String) -> Command {
  let env = self.env
  env.set(key, value)
  { ..self, env }
}

///|
pub fn Command::cwd(self : Command, dir : String) -> Command {
  { ..self, cwd: Some(dir) }
}

///|
pub fn Command::stdin(self : Command, stdio : Stdio) -> Command {
  { ..self, stdin: stdio }
}

///|
pub fn Command::stdout(self : Command, stdio : Stdio) -> Command {
  { ..self, stdout: stdio }
}

///|
pub fn Command::stderr(self : Command, stdio : Stdio) -> Command {
  { ..self, stderr: stdio }
}
