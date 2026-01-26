///|
/// Benchmarks for sandbox_async - async primitives and event loop

// ============ PollableFd Benchmarks ============

///|
test "bench: PollableFd create" (b : @bench.T) {
  let ctx = @posix.PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  let fd = ctx.open("/test.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::default_file())
  let result = b.bench(fn() {
    let _ = PollableFd::new(ctx, fd, @posix.POLLIN)
  })
  b.keep(result)
}

///|
test "bench: PollableFd is_ready file" (b : @bench.T) {
  let ctx = @posix.PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  let fd = ctx.open("/test.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::default_file())
  let pollable = PollableFd::new(ctx, fd, @posix.POLLIN)
  let result = b.bench(fn() {
    let _ = pollable.is_ready()
  })
  b.keep(result)
}

///|
test "bench: PollableFd is_ready pipe" (b : @bench.T) {
  let ctx = @posix.PosixContext::default()
  let pipe = ctx.pipe()
  let _ = try { ctx.write(pipe.write_fd, b"x") } catch { _ => 0 }
  let pollable = PollableFd::new(ctx, pipe.read_fd, @posix.POLLIN)
  let result = b.bench(fn() {
    let _ = pollable.is_ready()
  })
  b.keep(result)
}

// ============ TimerPollable Benchmarks ============

///|
test "bench: TimerPollable create" (b : @bench.T) {
  let ctx = @posix.PosixContext::default()
  ctx.set_mock_time(1000L)
  let result = b.bench(fn() {
    let _ = TimerPollable::new(ctx, 2000L * 1000000L)
  })
  b.keep(result)
}

///|
test "bench: TimerPollable is_ready" (b : @bench.T) {
  let ctx = @posix.PosixContext::default()
  ctx.set_mock_time(1000L)
  let timer = TimerPollable::new(ctx, 500L * 1000000L)  // Already expired
  let result = b.bench(fn() {
    let _ = timer.is_ready()
  })
  b.keep(result)
}

///|
test "bench: TimerPollable::after" (b : @bench.T) {
  let ctx = @posix.PosixContext::default()
  ctx.set_mock_time(1000L)
  let result = b.bench(fn() {
    let _ = TimerPollable::after(ctx, 500L * 1000000L)
  })
  b.keep(result)
}

// ============ AsyncPosixContext Benchmarks ============

///|
test "bench: AsyncPosixContext create" (b : @bench.T) {
  let ctx = @posix.PosixContext::default()
  let result = b.bench(fn() {
    let _ = AsyncPosixContext::new(ctx)
  })
  b.keep(result)
}

///|
test "bench: AsyncPosixContext subscribe_read" (b : @bench.T) {
  let ctx = @posix.PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  let fd = ctx.open("/test.txt", @posix.OpenFlags::from([@posix.O_RDONLY]), @posix.FileMode::default_file())
  let async_ctx = AsyncPosixContext::new(ctx)
  let result = b.bench(fn() {
    let _ = async_ctx.subscribe_read(fd)
  })
  b.keep(result)
}

///|
test "bench: AsyncPosixContext subscribe_duration" (b : @bench.T) {
  let ctx = @posix.PosixContext::default()
  ctx.set_mock_time(1000L)
  let async_ctx = AsyncPosixContext::new(ctx)
  let result = b.bench(fn() {
    let _ = async_ctx.subscribe_duration(500L * 1000000L)
  })
  b.keep(result)
}

// ============ Task Benchmarks ============

///|
test "bench: Task create" (b : @bench.T) {
  let result = b.bench(fn() {
    let _ = Task::new()
  })
  b.keep(result)
}

// ============ Coroutine Spawn Benchmark ============

///|
test "bench: coroutine spawn" (b : @bench.T) {
  let result = b.bench(fn() {
    let _ = @coroutine.spawn(async fn() { () })
  })
  b.keep(result)
}

///|
test "bench: coroutine spawn + reschedule" (b : @bench.T) {
  let result = b.bench(fn() {
    let _ = @coroutine.spawn(async fn() { () })
    @coroutine.reschedule()
  })
  b.keep(result)
}
