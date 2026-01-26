///|
test "@wasi.WasiSandboxConfig::default" {
  let config = @wasi.WasiSandboxConfig::default()
  assert_eq!(config.mode, @wasi.GuestOnly)
  assert_eq!(config.allow_network, false)
  assert_eq!(config.path_mappings.length(), 0)
}

///|
test "@wasi.WasiSandboxConfig::restricted" {
  let config = @wasi.WasiSandboxConfig::restricted()
  assert_eq!(config.mode, @wasi.HostEnforced)
  assert_eq!(config.allow_network, false)
  assert_eq!(config.caps.can_write, false)
}

///|
test "@wasi.WasiSandboxConfig::permissive" {
  let config = @wasi.WasiSandboxConfig::permissive()
  assert_eq!(config.mode, @wasi.Hybrid)
  assert_eq!(config.allow_network, true)
  assert_eq!(config.path_mappings.length(), 2)
}

///|
test "WasiSandboxConfig builder methods" {
  let config = @wasi.WasiSandboxConfig::default()
    .with_mode(@wasi.Hybrid)
    .with_network(true)
    .with_path_mapping("/app", "/tmp/app")
    .with_allowed_hosts(["localhost", "example.com"])
  assert_eq!(config.mode, @wasi.Hybrid)
  assert_eq!(config.allow_network, true)
  assert_eq!(config.path_mappings.length(), 1)
  inspect!(config.allowed_hosts, content="Some([\"localhost\", \"example.com\"])")
}

///|
test "WasiSandbox path mapping" {
  let config = @wasi.WasiSandboxConfig::default()
    .with_path_mapping("/sandbox", "/tmp/sandbox")
    .with_path_mapping("/home", "/tmp/home")
  let sandbox = @wasi.WasiSandbox::new(config)

  // Test exact match
  assert_eq!(sandbox.map_path("/sandbox"), "/tmp/sandbox")

  // Test prefix match
  assert_eq!(sandbox.map_path("/sandbox/file.txt"), "/tmp/sandbox/file.txt")
  assert_eq!(sandbox.map_path("/home/user"), "/tmp/home/user")

  // Test no match (returns original)
  assert_eq!(sandbox.map_path("/other/path"), "/other/path")
}

///|
test "@wasi.WasiSandbox::check_host" {
  // No network
  let no_net = @wasi.WasiSandbox::new(@wasi.WasiSandboxConfig::default())
  assert_eq!(no_net.check_host("localhost"), false)

  // With network, all hosts
  let all_hosts = @wasi.WasiSandbox::new(
    @wasi.WasiSandboxConfig::default().with_network(true)
  )
  // allowed_hosts is Some([]) in default, so no hosts allowed
  assert_eq!(all_hosts.check_host("localhost"), false)

  // With allowed hosts
  let restricted = @wasi.WasiSandbox::new(
    @wasi.WasiSandboxConfig::default()
      .with_network(true)
      .with_allowed_hosts(["localhost", "example.com"])
  )
  assert_eq!(restricted.check_host("localhost"), true)
  assert_eq!(restricted.check_host("example.com"), true)
  assert_eq!(restricted.check_host("evil.com"), false)
}

///|
test "WasiSandbox file operations" {
  let config = @wasi.WasiSandboxConfig::default().with_caps(@sandbox.Capabilities::unrestricted())
  let sandbox = @wasi.WasiSandbox::new(config)

  // Create directory
  sandbox.mkdir("/test")

  // Open and write file
  let fd = sandbox.open("/test/file.txt", @posix.OpenFlags::from([@posix.O_CREAT, O_RDWR]), @posix.FileMode::new(0o644))
  let _ = sandbox.write(fd, b"hello")
  sandbox.close(fd)

  // Read back
  let fd2 = sandbox.open("/test/file.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::new(0o644))
  let data = sandbox.read(fd2, 100)
  sandbox.close(fd2)

  assert_eq!(data, b"hello")
}

///|
test "WasiSandbox respects capabilities" {
  let config = @wasi.WasiSandboxConfig::restricted()  // read_only
  let sandbox = @wasi.WasiSandbox::new(config)

  // Should fail to write
  let result = try {
    sandbox.mkdir("/test")
    Ok(())
  } catch {
    @sandbox.SandboxError::PermissionDenied(_) => Err("denied")
    _ => Err("other")
  }
  assert_eq!(result, Err("denied"))
}
