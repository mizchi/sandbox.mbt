///|
/// Benchmarks for PosixContext

///|
test "bench: PosixContext open/close" (b : @bench.T) {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  let result = b.bench(fn() {
    try {
      let fd = ctx.open(
        "/test.txt",
        OpenFlags::from([O_RDONLY]),
        FileMode::default_file(),
      )
      ctx.close(fd)
    } catch {
      _ => ()
    }
  })
  b.keep(result)
}

///|
test "bench: PosixContext read" (b : @bench.T) {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello world test data")
  let fd = ctx.open(
    "/test.txt",
    OpenFlags::from([O_RDONLY]),
    FileMode::default_file(),
  )
  let result = b.bench(fn() {
    try {
      let _ = ctx.lseek(fd, 0L, SEEK_SET)
      let _ = ctx.read(fd, 100)
    } catch {
      _ => ()
    }
  })
  b.keep(result)
}

///|
test "bench: PosixContext write" (b : @bench.T) {
  let ctx = PosixContext::default()
  let fd = ctx.open(
    "/test.txt",
    OpenFlags::from([O_CREAT, O_RDWR]),
    FileMode::default_file(),
  )
  let data = b"hello world"
  let result = b.bench(fn() { let _ = ctx.write(fd, data) catch { _ => 0 } })
  b.keep(result)
}

///|
test "bench: PosixContext resolve_path" (b : @bench.T) {
  let ctx = PosixContext::default()
  let result = b.bench(fn() { let _ = ctx.resolve_path("./a/b/../c/./d") })
  b.keep(result)
}

///|
test "bench: PosixContext stat" (b : @bench.T) {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  let result = b.bench(fn() {
    try {
      let _ = ctx.stat("/test.txt")
    } catch {
      _ => ()
    }
  })
  b.keep(result)
}

///|
test "bench: PosixContext rename" (b : @bench.T) {
  let ctx = PosixContext::default()
  let mut i = 0
  let result = b.bench(fn() {
    let old_name = "/f" + i.to_string() + ".txt"
    let new_name = "/g" + i.to_string() + ".txt"
    try {
      ctx.get_fs().write_string(old_name, "data")
      ctx.rename(old_name, new_name)
    } catch {
      _ => ()
    }
    i = i + 1
  })
  b.keep(result)
}

///|
test "bench: PosixContext truncate" (b : @bench.T) {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello world this is test data")
  let result = b.bench(fn() {
    try {
      ctx.truncate("/test.txt", 10L)
      ctx.truncate("/test.txt", 30L)
    } catch {
      _ => ()
    }
  })
  b.keep(result)
}

///|
test "bench: PosixContext ftruncate" (b : @bench.T) {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello world this is test data")
  let fd = ctx.open(
    "/test.txt",
    OpenFlags::from([O_RDWR]),
    FileMode::default_file(),
  )
  let result = b.bench(fn() {
    try {
      ctx.ftruncate(fd, 10L)
      ctx.ftruncate(fd, 30L)
    } catch {
      _ => ()
    }
  })
  b.keep(result)
}

// ============ Poll Benchmarks ============

///|
test "bench: poll single fd ready" (b : @bench.T) {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  let fd = ctx.open(
    "/test.txt",
    OpenFlags::from([O_RDONLY]),
    FileMode::default_file(),
  )
  let pollfds = [PollFd::new(fd, POLLIN)]
  let result = b.bench(fn() {
    pollfds[0].clear_revents()
    let _ = ctx.poll(pollfds, 0)
  })
  b.keep(result)
}

///|
test "bench: poll multiple fds" (b : @bench.T) {
  let ctx = PosixContext::default()
  // Create 10 files
  for i in 0..<10 {
    ctx.get_fs().write_string("/f" + i.to_string() + ".txt", "data")
  }
  let pollfds : Array[PollFd] = []
  for i in 0..<10 {
    let fd = ctx.open(
      "/f" + i.to_string() + ".txt",
      OpenFlags::from([O_RDONLY]),
      FileMode::default_file(),
    )
    pollfds.push(PollFd::new(fd, POLLIN))
  }
  let result = b.bench(fn() {
    for pfd in pollfds {
      pfd.clear_revents()
    }
    let _ = ctx.poll(pollfds, 0)
  })
  b.keep(result)
}

///|
test "bench: poll pipe" (b : @bench.T) {
  let ctx = PosixContext::default()
  let pipe = ctx.pipe()
  // Write some data so read end is ready
  let _ = ctx.write(pipe.write_fd, b"x") catch { _ => 0 }
  let pollfds = [PollFd::new(pipe.read_fd, POLLIN)]
  let result = b.bench(fn() {
    pollfds[0].clear_revents()
    let _ = ctx.poll(pollfds, 0)
  })
  b.keep(result)
}

// ============ fcntl Benchmarks ============

///|
test "bench: fcntl_getfl" (b : @bench.T) {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  let fd = ctx.open(
    "/test.txt",
    OpenFlags::from([O_RDONLY]),
    FileMode::default_file(),
  )
  let result = b.bench(fn() {
    let _ = ctx.fcntl_getfl(fd) catch { _ => OpenFlags::new() }
  })
  b.keep(result)
}

///|
test "bench: fcntl_setfl" (b : @bench.T) {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  let fd = ctx.open(
    "/test.txt",
    OpenFlags::from([O_RDONLY]),
    FileMode::default_file(),
  )
  let flags = OpenFlags::from([O_RDONLY, O_NONBLOCK])
  let result = b.bench(fn() { ctx.fcntl_setfl(fd, flags) catch { _ => () } })
  b.keep(result)
}

///|
test "bench: fcntl_dupfd" (b : @bench.T) {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  let fd = ctx.open(
    "/test.txt",
    OpenFlags::from([O_RDONLY]),
    FileMode::default_file(),
  )
  let result = b.bench(fn() {
    try {
      let new_fd = ctx.fcntl_dupfd(fd, 100)
      ctx.close(new_fd)
    } catch {
      _ => ()
    }
  })
  b.keep(result)
}

// ============ access Benchmarks ============

///|
test "bench: access F_OK" (b : @bench.T) {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  let result = b.bench(fn() { ctx.access("/test.txt", F_OK) catch { _ => () } })
  b.keep(result)
}

///|
test "bench: access R_OK" (b : @bench.T) {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  let result = b.bench(fn() { ctx.access("/test.txt", R_OK) catch { _ => () } })
  b.keep(result)
}

// ============ Pipe Benchmarks ============

///|
test "bench: pipe create" (b : @bench.T) {
  let ctx = PosixContext::default()
  let result = b.bench(fn() {
    let pipe = ctx.pipe()
    try {
      ctx.close(pipe.read_fd)
      ctx.close(pipe.write_fd)
    } catch {
      _ => ()
    }
  })
  b.keep(result)
}

///|
test "bench: pipe write/read small" (b : @bench.T) {
  let ctx = PosixContext::default()
  let pipe = ctx.pipe()
  let data = b"hello"
  let result = b.bench(fn() {
    try {
      let _ = ctx.write(pipe.write_fd, data)
      let _ = ctx.read(pipe.read_fd, 10)
    } catch {
      _ => ()
    }
  })
  b.keep(result)
}

///|
test "bench: pipe write/read 1KB" (b : @bench.T) {
  let ctx = PosixContext::default()
  let pipe = ctx.pipe()
  let data = Bytes::make(1024, b'x')
  let result = b.bench(fn() {
    try {
      let _ = ctx.write(pipe.write_fd, data)
      let _ = ctx.read(pipe.read_fd, 1024)
    } catch {
      _ => ()
    }
  })
  b.keep(result)
}
