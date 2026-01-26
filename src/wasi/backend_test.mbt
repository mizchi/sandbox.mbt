// Tests for Backend configuration

test "sandbox mode" {
  let config = @wasi.RuntimeConfig::sandbox()
  assert_true(config.is_sandbox())
  assert_false(config.is_native())
  assert_true(config.get_fs() is Some(_))
}

test "sandbox with custom fs" {
  let fs = @fs.MemFS::new()
  fs.write_string("/test.txt", "hello")

  let config = @wasi.RuntimeConfig::sandbox_with(fs)
  assert_true(config.is_sandbox())

  match config.get_fs() {
    Some(f) => assert_true(f.exists("/test.txt"))
    None => assert_true(false)
  }
}

test "native mode" {
  let config = @wasi.RuntimeConfig::native()
  assert_true(config.is_native())
  assert_false(config.is_sandbox())
  assert_true(config.get_fs() is None)
}

test "with_config sandbox" {
  let config = @wasi.RuntimeConfig::sandbox()
  let ctx = @wasi.create_posix_context(config)

  // Should have default environment
  assert_eq(ctx.getenv("HOME"), Some("/home"))
  assert_eq(ctx.getcwd(), "/")
}

test "with_config custom fs" {
  let fs = @fs.MemFS::new()
  fs.mkdir("/custom")
  fs.write_string("/custom/data.txt", "test data")

  let config = @wasi.RuntimeConfig::sandbox_with(fs)
  let ctx = @wasi.create_posix_context(config)

  // Should be able to read the pre-created file
  let fd = ctx.open("/custom/data.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::default_file())
  let data = ctx.read(fd, 100)
  ctx.close(fd)

  assert_eq(data.length(), 9)  // "test data"
}

test "with_config native falls back to sandbox" {
  let config = @wasi.RuntimeConfig::native()
  let ctx = @wasi.create_posix_context(config)

  // Native mode currently falls back to sandbox
  assert_eq(ctx.getenv("HOME"), Some("/home"))
}

test "wasi_native mode" {
  let config = @wasi.RuntimeConfig::wasi_native()
  assert_true(config.is_wasi_native())
  assert_false(config.is_sandbox())
  assert_false(config.is_native())
  assert_true(config.get_wasi_config() is Some(_))
}

test "wasi_native with custom config" {
  let wasi_config = @wasi.WasiSandboxConfig::permissive()
    .with_path_mapping("/app", "/tmp/app")
  let config = @wasi.RuntimeConfig::wasi_native_with(wasi_config)

  assert_true(config.is_wasi_native())
  match config.get_wasi_config() {
    Some(c) => {
      assert_eq(c.mode, @wasi.Hybrid)
      assert_eq(c.allow_network, true)
    }
    None => assert_true(false)
  }
}

test "@wasi.WasiSandbox::with_config" {
  let config = @wasi.RuntimeConfig::wasi_native_with(
    @wasi.WasiSandboxConfig::default().with_caps(@sandbox.Capabilities::build_sandbox())
  )
  let sandbox = @wasi.WasiSandbox::with_config(config)

  // Should have build sandbox capabilities
  assert_eq(sandbox.get_config().caps.can_read, true)
  assert_eq(sandbox.get_config().caps.can_write, true)
}
