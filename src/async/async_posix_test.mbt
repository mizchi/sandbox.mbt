// Tests for AsyncPosixContext - Event Loop integration

///|
test "pollable_fd from pipe read end" {
  let ctx = @posix.PosixContext::default()
  let pipe = ctx.pipe()

  // Create pollable from read end
  let pollable = PollableFd::new(ctx, pipe.read_fd, @posix.POLLIN)

  // Not ready initially (no data)
  assert_false(pollable.is_ready())

  // Write data
  let _ = ctx.write(pipe.write_fd, Bytes::from_array([b'x']))

  // Now should be ready
  assert_true(pollable.is_ready())
  ctx.close(pipe.read_fd)
  ctx.close(pipe.write_fd)
}

///|
test "pollable_fd from pipe write end" {
  let ctx = @posix.PosixContext::default()
  let pipe = ctx.pipe()

  // Create pollable from write end
  let pollable = PollableFd::new(ctx, pipe.write_fd, @posix.POLLOUT)

  // Should be ready (can write)
  assert_true(pollable.is_ready())
  ctx.close(pipe.read_fd)
  ctx.close(pipe.write_fd)
}

///|
test "pollable_fd from regular file" {
  let ctx = @posix.PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  let fd = ctx.open(
    "/test.txt",
    @posix.OpenFlags::from([@posix.O_RDONLY]),
    @posix.FileMode::default_file(),
  )
  let pollable = PollableFd::new(ctx, fd, @posix.POLLIN)

  // Regular files are always ready
  assert_true(pollable.is_ready())
  ctx.close(fd)
}

// Helper struct for tracking async state

///|
struct AsyncTestState {
  mut done : Bool
  mut result_len : Int
  mut bytes_written : Int
}

///|
test "async_read from pipe" {
  // Setup
  let ctx = @posix.PosixContext::default()
  let pipe = ctx.pipe()
  let async_ctx = AsyncPosixContext::new(ctx)

  // Write data first
  let _ = ctx.write(pipe.write_fd, Bytes::from_array([b'h', b'i']))

  // Track state
  let state : AsyncTestState = { done: false, result_len: 0, bytes_written: 0 }
  let coro = @coroutine.spawn(async fn() {
    let data = async_ctx.read(pipe.read_fd, 10)
    state.result_len = data.length()
    state.done = true
  })

  // Run scheduler
  @coroutine.reschedule()

  // Should be done
  assert_true(state.done)
  assert_eq(state.result_len, 2)
  ignore(coro)
  ctx.close(pipe.read_fd)
  ctx.close(pipe.write_fd)
}

///|
test "async_write to pipe" {
  let ctx = @posix.PosixContext::default()
  let pipe = ctx.pipe()
  let async_ctx = AsyncPosixContext::new(ctx)
  let state : AsyncTestState = { done: false, result_len: 0, bytes_written: 0 }
  let coro = @coroutine.spawn(async fn() {
    let n = async_ctx.write(
      pipe.write_fd,
      Bytes::from_array([b'a', b'b', b'c']),
    )
    state.bytes_written = n
    state.done = true
  })
  @coroutine.reschedule()
  assert_true(state.done)
  assert_eq(state.bytes_written, 3)

  // Verify data was written
  let data = ctx.read(pipe.read_fd, 10)
  assert_eq(data.length(), 3)
  ignore(coro)
  ctx.close(pipe.read_fd)
  ctx.close(pipe.write_fd)
}

///|
test "wait_readable on pipe - already readable" {
  let ctx = @posix.PosixContext::default()
  let pipe = ctx.pipe()
  let async_ctx = AsyncPosixContext::new(ctx)

  // Write data first
  let _ = ctx.write(pipe.write_fd, Bytes::from_array([b'x']))
  let state : AsyncTestState = { done: false, result_len: 0, bytes_written: 0 }
  let coro = @coroutine.spawn(async fn() {
    async_ctx.wait_readable(pipe.read_fd)
    state.done = true
  })
  @coroutine.reschedule()

  // Should be done immediately since data was already written
  assert_true(state.done)
  ignore(coro)
  ctx.close(pipe.read_fd)
  ctx.close(pipe.write_fd)
}

///|
test "timer already expired" {
  let ctx = @posix.PosixContext::default()
  ctx.set_mock_time(1000L)

  // Deadline 500ms is already past
  let timer = TimerPollable::new(ctx, 500L * 1000000L)

  // At time 1000ms, deadline 500ms has passed
  assert_true(timer.is_ready())
}

///|
test "timer not ready then ready" {
  let ctx = @posix.PosixContext::default()
  ctx.set_mock_time(1000L)

  // Deadline at 2000ms (not yet reached)
  let timer = TimerPollable::new(ctx, 2000L * 1000000L)

  // At time 1000ms, deadline 2000ms not yet reached
  assert_false(timer.is_ready())

  // Advance time
  ctx.set_mock_time(2500L)
  assert_true(timer.is_ready())
}

///|
test "subscribe_duration creates timer" {
  let ctx = @posix.PosixContext::default()
  ctx.set_mock_time(1000L)
  let async_ctx = AsyncPosixContext::new(ctx)
  let timer = async_ctx.subscribe_duration(500L * 1000000L) // 500ms

  // Not ready yet
  assert_false(timer.is_ready())

  // Advance time by 600ms
  ctx.set_mock_time(1600L)
  assert_true(timer.is_ready())
}

///|
test "subscribe_read creates pollable" {
  let ctx = @posix.PosixContext::default()
  let pipe = ctx.pipe()
  let async_ctx = AsyncPosixContext::new(ctx)
  let pollable = async_ctx.subscribe_read(pipe.read_fd)

  // Not ready (no data)
  assert_false(pollable.is_ready())

  // Write data
  let _ = ctx.write(pipe.write_fd, Bytes::from_array([b'x']))

  // Now ready
  assert_true(pollable.is_ready())
  ctx.close(pipe.read_fd)
  ctx.close(pipe.write_fd)
}

///|
test "subscribe_write creates pollable" {
  let ctx = @posix.PosixContext::default()
  let pipe = ctx.pipe()
  let async_ctx = AsyncPosixContext::new(ctx)
  let pollable = async_ctx.subscribe_write(pipe.write_fd)

  // Should be ready (can write)
  assert_true(pollable.is_ready())
  ctx.close(pipe.read_fd)
  ctx.close(pipe.write_fd)
}
