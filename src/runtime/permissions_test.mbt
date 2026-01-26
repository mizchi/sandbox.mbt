///|
test "permissions: allow all" {
  let perms = Permissions::allow_all()

  let status = perms.query(PermissionDescriptor::Read(path=Some("/any/path")))
  assert_eq(status.state, PermissionState::Granted)

  let status2 = perms.query(PermissionDescriptor::Write(path=Some("/any/path")))
  assert_eq(status2.state, PermissionState::Granted)
}

///|
test "permissions: specific path allowed" {
  let perms = Permissions::new()
  perms.allow(PermissionDescriptor::Read(path=Some("/allowed")))

  // Allowed path
  let status = perms.query(PermissionDescriptor::Read(path=Some("/allowed")))
  assert_eq(status.state, PermissionState::Granted)

  // Subpath also allowed
  let status2 = perms.query(PermissionDescriptor::Read(path=Some("/allowed/subdir")))
  assert_eq(status2.state, PermissionState::Granted)

  // Different path not allowed
  let status3 = perms.query(PermissionDescriptor::Read(path=Some("/denied")))
  assert_eq(status3.state, PermissionState::Prompt)
}

///|
test "permissions: explicit deny" {
  let perms = Permissions::new()
  perms.allow(PermissionDescriptor::Read(path=None)) // Allow all read
  perms.deny(PermissionDescriptor::Read(path=Some("/secret"))) // But deny /secret

  let status = perms.query(PermissionDescriptor::Read(path=Some("/public")))
  assert_eq(status.state, PermissionState::Granted)

  let status2 = perms.query(PermissionDescriptor::Read(path=Some("/secret")))
  assert_eq(status2.state, PermissionState::Denied)
}

///|
test "permissions: env variables" {
  let perms = Permissions::new()
  perms.allow(PermissionDescriptor::Env(variable=Some("HOME")))
  perms.allow(PermissionDescriptor::Env(variable=Some("PATH")))

  let status = perms.query(PermissionDescriptor::Env(variable=Some("HOME")))
  assert_eq(status.state, PermissionState::Granted)

  let status2 = perms.query(PermissionDescriptor::Env(variable=Some("SECRET")))
  assert_eq(status2.state, PermissionState::Prompt)
}

///|
test "sandboxed backend: read allowed" {
  let perms = Permissions::new()
  perms.allow(PermissionDescriptor::Read(path=Some("/allowed")))
  perms.allow(PermissionDescriptor::Write(path=Some("/allowed")))

  let backend = SandboxedBackend::new(perms)

  // Create directory first
  backend.mkdir("/allowed")

  // Create file in allowed path
  let fd = backend.open("/allowed/test.txt", OpenFlags::create())
  let _ = backend.write(fd, b"hello")
  backend.close(fd)

  // Read should work
  let fd2 = backend.open("/allowed/test.txt", OpenFlags::read_only())
  let data = backend.read(fd2, 100)
  backend.close(fd2)

  assert_eq(data, b"hello")
}

///|
test "sandboxed backend: read denied" {
  let perms = Permissions::new()
  perms.allow(PermissionDescriptor::Read(path=Some("/allowed")))

  let backend = SandboxedBackend::new(perms)

  let result : Result[Fd, IOError] = try {
    Ok(backend.open("/denied/test.txt", OpenFlags::read_only()))
  } catch {
    e => Err(e)
  }

  assert_true(result is Err(IOError::PermissionDenied(_)))
}

///|
test "sandboxed backend: write denied" {
  let perms = Permissions::new()
  perms.allow(PermissionDescriptor::Read(path=None)) // Allow all read

  let backend = SandboxedBackend::new(perms)

  let result : Result[Fd, IOError] = try {
    Ok(backend.open("/test.txt", OpenFlags::create()))
  } catch {
    e => Err(e)
  }

  assert_true(result is Err(IOError::PermissionDenied(_)))
}

///|
test "sandboxed backend: process run denied" {
  let perms = Permissions::new()
  perms.allow(PermissionDescriptor::Run(command=Some("ls")))

  let backend = SandboxedBackend::new(perms)
  backend.register_builtins()

  // ls should work
  let result_ls : Result[Process, ProcessError] = try {
    Ok(backend.spawn(Command::new("ls")))
  } catch {
    e => Err(e)
  }
  assert_true(result_ls is Ok(_))

  // rm should be denied
  let result_rm : Result[Process, ProcessError] = try {
    Ok(backend.spawn(Command::new("rm")))
  } catch {
    e => Err(e)
  }
  assert_true(result_rm is Err(_))
}

///|
test "sandboxed backend: env filtered" {
  let perms = Permissions::new()
  perms.allow(PermissionDescriptor::Env(variable=Some("HOME")))

  let backend = SandboxedBackend::new(perms)

  // HOME should be accessible
  assert_eq(backend.get_env("HOME"), Some("/home"))

  // PATH should not be accessible (returns None)
  assert_eq(backend.get_env("PATH"), None)

  // env_vars should only return allowed vars
  let vars = backend.env_vars()
  assert_true(vars.contains("HOME"))
  assert_false(vars.contains("PATH"))
}
