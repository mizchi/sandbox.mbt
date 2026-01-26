/// Deno-like Permission System

///|
/// Permission state
pub(all) enum PermissionState {
  Granted
  Prompt
  Denied
} derive(Show, Eq)

///|
/// Permission descriptor
pub(all) enum PermissionDescriptor {
  Read(path~ : String?)
  Write(path~ : String?)
  Net(host~ : String?)
  Env(variable~ : String?)
  Run(command~ : String?)
} derive(Show, Eq)

///|
/// Permission status
pub(all) struct PermissionStatus {
  state : PermissionState
  descriptor : PermissionDescriptor
}

///|
/// Permissions manager
pub struct Permissions {
  allowed : Array[PermissionDescriptor]
  denied : Array[PermissionDescriptor]
}

///|
pub fn Permissions::new() -> Permissions {
  { allowed: [], denied: [] }
}

///|
pub fn Permissions::allow_all() -> Permissions {
  {
    allowed: [
      PermissionDescriptor::Read(path=None),
      PermissionDescriptor::Write(path=None),
      PermissionDescriptor::Net(host=None),
      PermissionDescriptor::Env(variable=None),
      PermissionDescriptor::Run(command=None),
    ],
    denied: [],
  }
}

///|
pub fn Permissions::allow(
  self : Permissions,
  desc : PermissionDescriptor,
) -> Unit {
  self.allowed.push(desc)
}

///|
pub fn Permissions::deny(
  self : Permissions,
  desc : PermissionDescriptor,
) -> Unit {
  self.denied.push(desc)
}

///|
pub fn Permissions::query(
  self : Permissions,
  desc : PermissionDescriptor,
) -> PermissionStatus {
  // Check denied first
  if self.is_denied(desc) {
    return { state: PermissionState::Denied, descriptor: desc }
  }

  // Check allowed
  if self.is_allowed(desc) {
    return { state: PermissionState::Granted, descriptor: desc }
  }

  // Default to prompt (but in WASM, this means denied)
  { state: PermissionState::Prompt, descriptor: desc }
}

///|
fn Permissions::is_denied(
  self : Permissions,
  desc : PermissionDescriptor,
) -> Bool {
  for d in self.denied {
    if matches_permission(d, desc) {
      return true
    }
  }
  false
}

///|
fn Permissions::is_allowed(
  self : Permissions,
  desc : PermissionDescriptor,
) -> Bool {
  for d in self.allowed {
    if matches_permission(d, desc) {
      return true
    }
  }
  false
}

///|
/// Check if allowed permission covers requested permission
fn matches_permission(
  allowed : PermissionDescriptor,
  requested : PermissionDescriptor,
) -> Bool {
  match (allowed, requested) {
    (PermissionDescriptor::Read(path=None), PermissionDescriptor::Read(_)) =>
      true
    (
      PermissionDescriptor::Read(path=Some(allowed_path)),
      PermissionDescriptor::Read(path=Some(req_path)),
    ) => is_subpath(allowed_path, req_path)
    (PermissionDescriptor::Write(path=None), PermissionDescriptor::Write(_)) =>
      true
    (
      PermissionDescriptor::Write(path=Some(allowed_path)),
      PermissionDescriptor::Write(path=Some(req_path)),
    ) => is_subpath(allowed_path, req_path)
    (PermissionDescriptor::Net(host=None), PermissionDescriptor::Net(_)) => true
    (
      PermissionDescriptor::Net(host=Some(allowed_host)),
      PermissionDescriptor::Net(host=Some(req_host)),
    ) => allowed_host == req_host
    (PermissionDescriptor::Env(variable=None), PermissionDescriptor::Env(_)) =>
      true
    (
      PermissionDescriptor::Env(variable=Some(allowed_var)),
      PermissionDescriptor::Env(variable=Some(req_var)),
    ) => allowed_var == req_var
    (PermissionDescriptor::Run(command=None), PermissionDescriptor::Run(_)) =>
      true
    (
      PermissionDescriptor::Run(command=Some(allowed_cmd)),
      PermissionDescriptor::Run(command=Some(req_cmd)),
    ) => allowed_cmd == req_cmd
    _ => false
  }
}

///|
/// Check if requested path is under allowed path
fn is_subpath(allowed : String, requested : String) -> Bool {
  if requested == allowed {
    return true
  }
  if requested.has_prefix(allowed) {
    // Make sure it's a proper subpath (not just prefix match)
    let suffix = requested.substring(start=allowed.length())
    return suffix.has_prefix("/")
  }
  false
}

///|
/// Permission denied error
pub(all) suberror PermissionDenied {
  Read(String)
  Write(String)
  Net(String)
  Env(String)
  Run(String)
} derive(Show, Eq)

///|
/// Check read permission
pub fn Permissions::check_read(
  self : Permissions,
  path : String,
) -> Unit raise PermissionDenied {
  let status = self.query(PermissionDescriptor::Read(path=Some(path)))
  if status.state != PermissionState::Granted {
    raise PermissionDenied::Read(path)
  }
}

///|
/// Check write permission
pub fn Permissions::check_write(
  self : Permissions,
  path : String,
) -> Unit raise PermissionDenied {
  let status = self.query(PermissionDescriptor::Write(path=Some(path)))
  if status.state != PermissionState::Granted {
    raise PermissionDenied::Write(path)
  }
}

///|
/// Check net permission
pub fn Permissions::check_net(
  self : Permissions,
  host : String,
) -> Unit raise PermissionDenied {
  let status = self.query(PermissionDescriptor::Net(host=Some(host)))
  if status.state != PermissionState::Granted {
    raise PermissionDenied::Net(host)
  }
}

///|
/// Check env permission
pub fn Permissions::check_env(
  self : Permissions,
  variable : String,
) -> Unit raise PermissionDenied {
  let status = self.query(PermissionDescriptor::Env(variable=Some(variable)))
  if status.state != PermissionState::Granted {
    raise PermissionDenied::Env(variable)
  }
}

///|
/// Check run permission
pub fn Permissions::check_run(
  self : Permissions,
  command : String,
) -> Unit raise PermissionDenied {
  let status = self.query(PermissionDescriptor::Run(command=Some(command)))
  if status.state != PermissionState::Granted {
    raise PermissionDenied::Run(command)
  }
}
