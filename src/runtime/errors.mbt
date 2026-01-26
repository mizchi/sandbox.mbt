/// Runtime errors

///|
/// IO Error
pub(all) suberror IOError {
  NotFound(String)
  PermissionDenied(String)
  AlreadyExists(String)
  IsDirectory(String)
  NotDirectory(String)
  InvalidInput(String)
  BrokenPipe
  Closed
  Other(String)
} derive(Show, Eq)

///|
/// Process Error
pub(all) suberror ProcessError {
  NotFound(String)
  NotSupported(String)
  InvalidPid(Pid)
  AlreadyExited(Pid)
  SpawnFailed(String)
  Other(String)
} derive(Show, Eq)

///|
/// Network Error
pub(all) suberror NetworkError {
  ConnectionRefused(String)
  ConnectionReset
  ConnectionClosed
  AddrInUse(String)
  AddrNotAvailable(String)
  PermissionDenied(String)
  Timeout
  HostNotFound(String)
  Other(String)
} derive(Show, Eq)
