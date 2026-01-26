///|
/// Benchmarks for Sandbox and Capabilities

///|
test "bench: Sandbox open with capability check" (b : @bench.T) {
  let sandbox = Sandbox::new(Capabilities::unrestricted())
  sandbox.get_ctx().get_fs().write_string("/test.txt", "hello")
  let result = b.bench(fn() {
    try {
      let fd = sandbox.open("/test.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::default_file())
      sandbox.close(fd)
    } catch { _ => () }
  })
  b.keep(result)
}

///|
test "bench: Sandbox path check allowed" (b : @bench.T) {
  let caps = Capabilities::build_sandbox()
  let sandbox = Sandbox::new(caps)
  // Create /tmp directory
  sandbox.get_ctx().get_fs().mkdir("/tmp")
  let result = b.bench(fn() {
    // This will check if path is in allowed list
    try {
      let fd = sandbox.open("/tmp/test.txt", @posix.OpenFlags::from([@posix.O_CREAT, @posix.O_RDWR]), @posix.FileMode::default_file())
      sandbox.close(fd)
    } catch {
      _ => ()
    }
  })
  b.keep(result)
}

///|
test "bench: Sandbox capability check overhead" (b : @bench.T) {
  // Measure overhead of capability checks vs raw MemFS
  let sandbox = Sandbox::new(Capabilities::unrestricted())
  let ctx = sandbox.get_ctx()
  ctx.get_fs().write_string("/test.txt", "hello")

  // With sandbox (capability checks)
  let result = b.bench(fn() {
    try {
      let fd = sandbox.open("/test.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::default_file())
      let _ = sandbox.read(fd, 100)
      sandbox.close(fd)
    } catch { _ => () }
  })
  b.keep(result)
}

///|
test "bench: Raw PosixContext (no sandbox)" (b : @bench.T) {
  // Baseline without sandbox for comparison
  let ctx = @posix.PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")

  let result = b.bench(fn() {
    try {
      let fd = ctx.open("/test.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::default_file())
      let _ = ctx.read(fd, 100)
      ctx.close(fd)
    } catch { _ => () }
  })
  b.keep(result)
}

// ============ Capabilities Benchmarks ============

///|
test "bench: Capabilities creation" (b : @bench.T) {
  let result = b.bench(fn() {
    let _ = Capabilities::build_sandbox()
  })
  b.keep(result)
}

///|
test "bench: Capabilities with_allowed_paths" (b : @bench.T) {
  let caps = Capabilities::build_sandbox()
  let result = b.bench(fn() {
    let _ = caps.with_allowed_paths(["/tmp", "/home", "/var", "/sandbox", "/app"])
  })
  b.keep(result)
}
