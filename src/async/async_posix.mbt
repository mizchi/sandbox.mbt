/// AsyncPosixContext - Event Loop integration for POSIX operations
///
/// Provides async versions of POSIX operations that integrate with
/// the coroutine scheduler.

///|
/// Pollable file descriptor - implements Waitable
pub struct PollableFd {
  ctx : @posix.PosixContext
  fd : @posix.Fd
  events : @posix.PollEvent
  mut waiter : @coroutine.Coroutine?
}

///|
/// Create a new pollable fd
pub fn PollableFd::new(
  ctx : @posix.PosixContext,
  fd : @posix.Fd,
  events : @posix.PollEvent,
) -> PollableFd {
  { ctx, fd, events, waiter: None }
}

///|
/// Check if fd is ready for the requested operation
pub fn PollableFd::is_ready(self : PollableFd) -> Bool {
  let pollfds = [@posix.PollFd::new(self.fd, self.events)]
  let ready = self.ctx.poll(pollfds, 0)
  ready > 0 && pollfds[0].has_revent(self.events)
}

///|
/// Get waiter coroutine
pub fn PollableFd::get_waiter(self : PollableFd) -> @coroutine.Coroutine? {
  self.waiter
}

///|
/// Set waiter coroutine
pub fn PollableFd::set_waiter(
  self : PollableFd,
  coro : @coroutine.Coroutine?,
) -> Unit {
  self.waiter = coro
}

// Implement Waitable trait for PollableFd

///|
pub impl Waitable for PollableFd with is_ready(self) {
  self.is_ready()
}

///|
pub impl Waitable for PollableFd with get_waiter(self) {
  self.waiter
}

///|
pub impl Waitable for PollableFd with set_waiter(self, coro) {
  self.waiter = coro
}

///|
/// Timer pollable - waits until a deadline
pub struct TimerPollable {
  ctx : @posix.PosixContext
  deadline_ns : Int64 // Deadline in nanoseconds (mock time)
  mut waiter : @coroutine.Coroutine?
}

///|
/// Create a timer that is ready when deadline has passed
pub fn TimerPollable::new(
  ctx : @posix.PosixContext,
  deadline_ns : Int64,
) -> TimerPollable {
  { ctx, deadline_ns, waiter: None }
}

///|
/// Create a timer that fires after duration_ns nanoseconds
pub fn TimerPollable::after(
  ctx : @posix.PosixContext,
  duration_ns : Int64,
) -> TimerPollable {
  let now = ctx.get_time() * 1000000L // Convert ms to ns
  TimerPollable::new(ctx, now + duration_ns)
}

///|
/// Check if timer has expired
pub fn TimerPollable::is_ready(self : TimerPollable) -> Bool {
  let now = self.ctx.get_time() * 1000000L // Convert ms to ns
  now >= self.deadline_ns
}

// Implement Waitable for TimerPollable

///|
pub impl Waitable for TimerPollable with is_ready(self) {
  self.is_ready()
}

///|
pub impl Waitable for TimerPollable with get_waiter(self) {
  self.waiter
}

///|
pub impl Waitable for TimerPollable with set_waiter(self, coro) {
  self.waiter = coro
}

///|
/// Async POSIX context - provides async operations
pub struct AsyncPosixContext {
  ctx : @posix.PosixContext
}

///|
/// Create a new async POSIX context
pub fn AsyncPosixContext::new(ctx : @posix.PosixContext) -> AsyncPosixContext {
  { ctx, }
}

///|
/// Get underlying sync context
pub fn AsyncPosixContext::get_ctx(
  self : AsyncPosixContext,
) -> @posix.PosixContext {
  self.ctx
}

///|
/// Wait until fd is readable
pub async fn AsyncPosixContext::wait_readable(
  self : AsyncPosixContext,
  fd : @posix.Fd,
) -> Unit {
  let pollable = PollableFd::new(self.ctx, fd, @posix.POLLIN)
  if pollable.is_ready() {
    return
  }

  // Not ready, suspend
  let current = @coroutine.current_coroutine()
  pollable.set_waiter(Some(current))
  @coroutine.suspend()
}

///|
/// Wait until fd is writable
pub async fn AsyncPosixContext::wait_writable(
  self : AsyncPosixContext,
  fd : @posix.Fd,
) -> Unit {
  let pollable = PollableFd::new(self.ctx, fd, @posix.POLLOUT)
  if pollable.is_ready() {
    return
  }
  let current = @coroutine.current_coroutine()
  pollable.set_waiter(Some(current))
  @coroutine.suspend()
}

///|
/// Async read - waits for data if not immediately available
pub async fn AsyncPosixContext::read(
  self : AsyncPosixContext,
  fd : @posix.Fd,
  count : Int,
) -> Bytes {
  // Wait until readable
  self.wait_readable(fd)

  // Now read
  self.ctx.read(fd, count)
}

///|
/// Async write - waits until writable
pub async fn AsyncPosixContext::write(
  self : AsyncPosixContext,
  fd : @posix.Fd,
  data : Bytes,
) -> Int {
  // Wait until writable
  self.wait_writable(fd)

  // Now write
  self.ctx.write(fd, data)
}

///|
/// Sleep for specified duration (in nanoseconds, using mock time)
pub async fn AsyncPosixContext::sleep_ns(
  self : AsyncPosixContext,
  duration_ns : Int64,
) -> Unit {
  let timer = TimerPollable::after(self.ctx, duration_ns)
  if timer.is_ready() {
    return
  }
  let current = @coroutine.current_coroutine()
  timer.set_waiter(Some(current))
  @coroutine.suspend()
}

///|
/// Sleep for specified duration (in milliseconds)
pub async fn AsyncPosixContext::sleep_ms(
  self : AsyncPosixContext,
  duration_ms : Int64,
) -> Unit {
  self.sleep_ns(duration_ms * 1000000L)
}

///|
/// Open a file asynchronously (sync for now, but async interface)
pub fn AsyncPosixContext::open(
  self : AsyncPosixContext,
  path : String,
  flags : @posix.OpenFlags,
  mode : @posix.FileMode,
) -> @posix.Fd raise @posix.PosixError {
  // File open is typically sync in most systems
  self.ctx.open(path, flags, mode)
}

///|
/// Close a file descriptor
pub fn AsyncPosixContext::close(
  self : AsyncPosixContext,
  fd : @posix.Fd,
) -> Unit raise @posix.PosixError {
  self.ctx.close(fd)
}

///|
/// Create pollable for reading
pub fn AsyncPosixContext::subscribe_read(
  self : AsyncPosixContext,
  fd : @posix.Fd,
) -> PollableFd {
  PollableFd::new(self.ctx, fd, @posix.POLLIN)
}

///|
/// Create pollable for writing
pub fn AsyncPosixContext::subscribe_write(
  self : AsyncPosixContext,
  fd : @posix.Fd,
) -> PollableFd {
  PollableFd::new(self.ctx, fd, @posix.POLLOUT)
}

///|
/// Create timer pollable
pub fn AsyncPosixContext::subscribe_duration(
  self : AsyncPosixContext,
  duration_ns : Int64,
) -> TimerPollable {
  TimerPollable::after(self.ctx, duration_ns)
}
