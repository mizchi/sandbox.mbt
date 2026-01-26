///|
/// Benchmarks for WasiSandbox

///|
test "bench: WasiSandbox open with mapping" (b : @bench.T) {
  let config = WasiSandboxConfig::default()
    .with_caps(@sandbox.Capabilities::unrestricted())
    .with_path_mapping("/sandbox", "/tmp")
  let wasi = WasiSandbox::new(config)
  wasi.get_sandbox().get_ctx().get_fs().mkdir("/tmp")
  wasi.get_sandbox().get_ctx().get_fs().write_string("/tmp/test.txt", "hello")

  let result = b.bench(fn() {
    try {
      let fd = wasi.open("/sandbox/test.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::default_file())
      wasi.close(fd)
    } catch { _ => () }
  })
  b.keep(result)
}

///|
test "bench: WasiSandbox path mapping" (b : @bench.T) {
  let config = WasiSandboxConfig::default()
    .with_path_mapping("/sandbox", "/tmp/sandbox")
    .with_path_mapping("/home", "/tmp/home")
    .with_path_mapping("/app", "/var/app")
  let wasi = WasiSandbox::new(config)

  let result = b.bench(fn() {
    let _ = wasi.map_path("/sandbox/deep/nested/path/file.txt")
  })
  b.keep(result)
}

///|
test "bench: WasiSandbox host check" (b : @bench.T) {
  let config = WasiSandboxConfig::default()
    .with_network(true)
    .with_allowed_hosts(["localhost", "example.com", "api.example.com", "cdn.example.org"])
  let wasi = WasiSandbox::new(config)

  let result = b.bench(fn() {
    let _ = wasi.check_host("api.example.com")
  })
  b.keep(result)
}

///|
test "bench: WasiSandbox full operation" (b : @bench.T) {
  // Full WASI sandbox operation: map path + capability check + open + read + close
  let config = WasiSandboxConfig::default()
    .with_caps(@sandbox.Capabilities::unrestricted())
    .with_path_mapping("/sandbox", "/tmp")
  let wasi = WasiSandbox::new(config)
  wasi.get_sandbox().get_ctx().get_fs().mkdir("/tmp")
  wasi.get_sandbox().get_ctx().get_fs().write_string("/tmp/test.txt", "hello world data")

  let result = b.bench(fn() {
    try {
      let fd = wasi.open("/sandbox/test.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::default_file())
      let _ = wasi.read(fd, 100)
      wasi.close(fd)
    } catch { _ => () }
  })
  b.keep(result)
}

// ============ Comparison: Layer Overhead ============

///|
test "bench: Layer 0 - Direct MemFS" (b : @bench.T) {
  let fs = @fs.MemFS::new()
  fs.write_string("/test.txt", "benchmark data")
  let result = b.bench(fn() {
    let _ = try { fs.read_string("/test.txt") } catch { _ => "" }
  })
  b.keep(result)
}

///|
test "bench: Layer 1 - PosixContext" (b : @bench.T) {
  let ctx = @posix.PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "benchmark data")
  let fd = ctx.open("/test.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::default_file())
  let result = b.bench(fn() {
    try {
      let _ = ctx.lseek(fd, 0L, @posix.SEEK_SET)
      let _ = ctx.read(fd, 100)
    } catch { _ => () }
  })
  b.keep(result)
}

///|
test "bench: Layer 2 - Sandbox" (b : @bench.T) {
  let sandbox = @sandbox.Sandbox::new(@sandbox.Capabilities::unrestricted())
  sandbox.get_ctx().get_fs().write_string("/test.txt", "benchmark data")
  let fd = sandbox.open("/test.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::default_file())
  let result = b.bench(fn() {
    try {
      // Re-seek and read
      let _ = sandbox.get_ctx().lseek(fd, 0L, @posix.SEEK_SET)
      let _ = sandbox.read(fd, 100)
    } catch { _ => () }
  })
  b.keep(result)
}

///|
test "bench: Layer 3 - WasiSandbox" (b : @bench.T) {
  let config = WasiSandboxConfig::default().with_caps(@sandbox.Capabilities::unrestricted())
  let wasi = WasiSandbox::new(config)
  wasi.get_sandbox().get_ctx().get_fs().write_string("/test.txt", "benchmark data")
  let fd = wasi.open("/test.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::default_file())
  let result = b.bench(fn() {
    try {
      let _ = wasi.get_sandbox().get_ctx().lseek(fd, 0L, @posix.SEEK_SET)
      let _ = wasi.read(fd, 100)
    } catch { _ => () }
  })
  b.keep(result)
}
