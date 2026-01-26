///|
test "cli parser: allow all" {
  let parsed = parse_args(["--allow-all", "--", "arg1", "arg2"])

  let status = parsed.permissions.query(PermissionDescriptor::Read(path=Some("/any")))
  assert_eq(status.state, PermissionState::Granted)

  assert_eq(parsed.program_args, ["arg1", "arg2"])
}

///|
test "cli parser: specific paths" {
  let parsed = parse_args([
    "--allow-read=/data",
    "--allow-write=/tmp",
    "--deny-write=/tmp/secret",
  ])

  // /data readable
  let s1 = parsed.permissions.query(PermissionDescriptor::Read(path=Some("/data/file.txt")))
  assert_eq(s1.state, PermissionState::Granted)

  // /other not readable
  let s2 = parsed.permissions.query(PermissionDescriptor::Read(path=Some("/other")))
  assert_eq(s2.state, PermissionState::Prompt)

  // /tmp writable
  let s3 = parsed.permissions.query(PermissionDescriptor::Write(path=Some("/tmp/file.txt")))
  assert_eq(s3.state, PermissionState::Granted)

  // /tmp/secret denied
  let s4 = parsed.permissions.query(PermissionDescriptor::Write(path=Some("/tmp/secret/file.txt")))
  assert_eq(s4.state, PermissionState::Denied)
}

///|
test "cli parser: env and run" {
  let parsed = parse_args([
    "--allow-env=HOME",
    "--allow-env=PATH",
    "--allow-run=ls",
    "--allow-run=cat",
  ])

  let s1 = parsed.permissions.query(PermissionDescriptor::Env(variable=Some("HOME")))
  assert_eq(s1.state, PermissionState::Granted)

  let s2 = parsed.permissions.query(PermissionDescriptor::Env(variable=Some("SECRET")))
  assert_eq(s2.state, PermissionState::Prompt)

  let s3 = parsed.permissions.query(PermissionDescriptor::Run(command=Some("ls")))
  assert_eq(s3.state, PermissionState::Granted)

  let s4 = parsed.permissions.query(PermissionDescriptor::Run(command=Some("rm")))
  assert_eq(s4.state, PermissionState::Prompt)
}

///|
test "cli parser: create sandbox" {
  let (backend, args) = create_sandbox_from_args([
    "--allow-read=/data",
    "--allow-write=/data",
    "--allow-run=echo",
    "--",
    "hello",
  ])

  backend.register_builtins()
  backend.mkdir("/data")

  // Should work
  let fd = backend.open("/data/test.txt", OpenFlags::create())
  backend.close(fd)

  assert_eq(args, ["hello"])
}
