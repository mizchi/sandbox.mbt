/// Sandboxed Backend - MemfsBackend with Permission Checking

///|
/// Sandboxed backend wrapping MemfsBackend with permissions
pub struct SandboxedBackend {
  inner : MemfsBackend
  permissions : Permissions
}

///|
pub fn SandboxedBackend::new(permissions : Permissions) -> SandboxedBackend {
  { inner: MemfsBackend::new(), permissions }
}

///|
pub fn SandboxedBackend::with_backend(
  backend : MemfsBackend,
  permissions : Permissions,
) -> SandboxedBackend {
  { inner: backend, permissions }
}

///|
pub fn SandboxedBackend::register(
  self : SandboxedBackend,
  name : String,
  handler : (ProcessContext) -> Int,
) -> Unit {
  self.inner.register(name, handler)
}

///|
pub fn SandboxedBackend::register_builtins(self : SandboxedBackend) -> Unit {
  self.inner.register_builtins()
}

///|
fn convert_permission_error(e : PermissionDenied) -> IOError {
  match e {
    PermissionDenied::Read(p) => IOError::PermissionDenied("read: \{p}")
    PermissionDenied::Write(p) => IOError::PermissionDenied("write: \{p}")
    PermissionDenied::Net(h) => IOError::PermissionDenied("net: \{h}")
    PermissionDenied::Env(v) => IOError::PermissionDenied("env: \{v}")
    PermissionDenied::Run(c) => IOError::PermissionDenied("run: \{c}")
  }
}

// ============ Filesystem implementation with permission checks ============

///|
pub impl Filesystem for SandboxedBackend with open(self, path, flags) {
  let abs_path = self.inner.resolve_path(path)

  // Check read permission if reading
  if flags.is_readable() {
    self.permissions.check_read(abs_path) catch {
      e => raise convert_permission_error(e)
    }
  }

  // Check write permission if writing
  if flags.is_writable() {
    self.permissions.check_write(abs_path) catch {
      e => raise convert_permission_error(e)
    }
  }
  self.inner.open(path, flags)
}

///|
pub impl Filesystem for SandboxedBackend with read(self, fd, len) {
  self.inner.read(fd, len)
}

///|
pub impl Filesystem for SandboxedBackend with write(self, fd, data) {
  self.inner.write(fd, data)
}

///|
pub impl Filesystem for SandboxedBackend with close(self, fd) {
  self.inner.close(fd)
}

///|
pub impl Filesystem for SandboxedBackend with stat(self, path) {
  let abs_path = self.inner.resolve_path(path)
  self.permissions.check_read(abs_path) catch {
    e => raise convert_permission_error(e)
  }
  self.inner.stat(path)
}

///|
pub impl Filesystem for SandboxedBackend with exists(self, path) {
  let abs_path = self.inner.resolve_path(path)
  let result : Result[Unit, PermissionDenied] = try {
    self.permissions.check_read(abs_path)
    Ok(())
  } catch {
    e => Err(e)
  }
  match result {
    Ok(_) => self.inner.exists(path)
    Err(_) => false
  }
}

///|
pub impl Filesystem for SandboxedBackend with mkdir(self, path) {
  let abs_path = self.inner.resolve_path(path)
  self.permissions.check_write(abs_path) catch {
    e => raise convert_permission_error(e)
  }
  self.inner.mkdir(path)
}

///|
pub impl Filesystem for SandboxedBackend with readdir(self, path) {
  let abs_path = self.inner.resolve_path(path)
  self.permissions.check_read(abs_path) catch {
    e => raise convert_permission_error(e)
  }
  self.inner.readdir(path)
}

///|
pub impl Filesystem for SandboxedBackend with unlink(self, path) {
  let abs_path = self.inner.resolve_path(path)
  self.permissions.check_write(abs_path) catch {
    e => raise convert_permission_error(e)
  }
  self.inner.unlink(path)
}

///|
pub impl Filesystem for SandboxedBackend with rename(self, from, to) {
  let abs_from = self.inner.resolve_path(from)
  let abs_to = self.inner.resolve_path(to)
  self.permissions.check_read(abs_from) catch {
    e => raise convert_permission_error(e)
  }
  self.permissions.check_write(abs_to) catch {
    e => raise convert_permission_error(e)
  }
  self.inner.rename(from, to)
}

///|
pub impl Filesystem for SandboxedBackend with realpath(self, path) {
  self.inner.realpath(path)
}

// ============ ProcessManager implementation ============

///|
fn convert_permission_to_process_error(e : PermissionDenied) -> ProcessError {
  match e {
    PermissionDenied::Run(c) => ProcessError::NotSupported("run denied: \{c}")
    _ => ProcessError::Other("permission denied")
  }
}

///|
pub impl ProcessManager for SandboxedBackend with spawn(self, cmd) {
  self.permissions.check_run(cmd.program) catch {
    e => raise convert_permission_to_process_error(e)
  }
  self.inner.spawn(cmd)
}

///|
pub impl ProcessManager for SandboxedBackend with wait(self, pid) {
  self.inner.wait(pid)
}

///|
pub impl ProcessManager for SandboxedBackend with try_wait(self, pid) {
  self.inner.try_wait(pid)
}

///|
pub impl ProcessManager for SandboxedBackend with kill(self, pid, signal) {
  self.inner.kill(pid, signal)
}

///|
pub impl ProcessManager for SandboxedBackend with current_pid(self) {
  self.inner.current_pid()
}

///|
pub impl ProcessManager for SandboxedBackend with read_stdout(self, pid) {
  self.inner.read_stdout(pid)
}

///|
pub impl ProcessManager for SandboxedBackend with read_stderr(self, pid) {
  self.inner.read_stderr(pid)
}

///|
pub impl ProcessManager for SandboxedBackend with write_stdin(self, pid, data) {
  self.inner.write_stdin(pid, data)
}

///|
pub impl ProcessManager for SandboxedBackend with read_stdout_bytes(self, pid) {
  self.inner.read_stdout_bytes(pid)
}

///|
pub impl ProcessManager for SandboxedBackend with read_stderr_bytes(self, pid) {
  self.inner.read_stderr_bytes(pid)
}

///|
pub impl ProcessManager for SandboxedBackend with write_stdin_bytes(self, pid, data) {
  self.inner.write_stdin_bytes(pid, data)
}

///|
pub impl ProcessManager for SandboxedBackend with close_stdin(self, pid) {
  self.inner.close_stdin(pid)
}

// ============ Network implementation ============

///|
fn convert_permission_to_network_error(e : PermissionDenied) -> NetworkError {
  match e {
    PermissionDenied::Net(h) =>
      NetworkError::PermissionDenied("net denied: \{h}")
    _ => NetworkError::Other("permission denied")
  }
}

///|
pub impl Network for SandboxedBackend with tcp_connect(self, addr) {
  let host = "\{addr.host}:\{addr.port}"
  self.permissions.check_net(host) catch {
    e => raise convert_permission_to_network_error(e)
  }
  self.inner.tcp_connect(addr)
}

///|
pub impl Network for SandboxedBackend with tcp_read(self, conn, len) {
  self.inner.tcp_read(conn, len)
}

///|
pub impl Network for SandboxedBackend with tcp_write(self, conn, data) {
  self.inner.tcp_write(conn, data)
}

///|
pub impl Network for SandboxedBackend with tcp_close(self, conn) {
  self.inner.tcp_close(conn)
}

///|
pub impl Network for SandboxedBackend with tcp_listen(self, addr) {
  let host = "\{addr.host}:\{addr.port}"
  self.permissions.check_net(host) catch {
    e => raise convert_permission_to_network_error(e)
  }
  self.inner.tcp_listen(addr)
}

///|
pub impl Network for SandboxedBackend with tcp_accept(self, listener) {
  self.inner.tcp_accept(listener)
}

///|
pub impl Network for SandboxedBackend with tcp_listener_close(self, listener) {
  self.inner.tcp_listener_close(listener)
}

///|
pub impl Network for SandboxedBackend with resolve(self, host) {
  self.permissions.check_net(host) catch {
    e => raise convert_permission_to_network_error(e)
  }
  self.inner.resolve(host)
}

// ============ Environment implementation ============

///|
pub impl Environment for SandboxedBackend with get_env(self, name) {
  let result : Result[Unit, PermissionDenied] = try {
    self.permissions.check_env(name)
    Ok(())
  } catch {
    e => Err(e)
  }
  match result {
    Ok(_) => self.inner.get_env(name)
    Err(_) => None
  }
}

///|
pub impl Environment for SandboxedBackend with set_env(self, name, value) {
  let result : Result[Unit, PermissionDenied] = try {
    self.permissions.check_env(name)
    Ok(())
  } catch {
    _ => Err(PermissionDenied::Env(name))
  }
  match result {
    Ok(_) => self.inner.set_env(name, value)
    Err(_) => () // Silently fail
  }
}

///|
pub impl Environment for SandboxedBackend with env_vars(self) {
  // Only return env vars that are allowed
  let filtered : Map[String, String] = {}
  for k, v in self.inner.env_vars() {
    let result : Result[Unit, PermissionDenied] = try {
      self.permissions.check_env(k)
      Ok(())
    } catch {
      e => Err(e)
    }
    if result is Ok(_) {
      filtered.set(k, v)
    }
  }
  filtered
}

///|
pub impl Environment for SandboxedBackend with args(self) {
  self.inner.args()
}

///|
pub impl Environment for SandboxedBackend with cwd(self) {
  self.inner.cwd()
}

///|
pub impl Environment for SandboxedBackend with chdir(self, path) {
  let abs_path = self.inner.resolve_path(path)
  self.permissions.check_read(abs_path) catch {
    e => raise convert_permission_error(e)
  }
  self.inner.chdir(path)
}
