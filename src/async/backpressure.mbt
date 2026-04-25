/// Backpressure - WASI 0.3 backpressure mechanism
///
/// Controls the rate of incoming async calls to prevent overload

///|
/// Backpressure controller
pub struct BackpressureController {
  mut active : Bool
  mut max_concurrent : Int
  mut current_count : Int
  waiters : Array[@coroutine.Coroutine]
}

///|
/// Wake all waiters
fn BackpressureController::wake_all(self : BackpressureController) -> Unit {
  for coro in self.waiters {
    coro.wake()
  }
  self.waiters.clear()
}

///|
/// Wake one waiter if present
fn BackpressureController::wake_one(self : BackpressureController) -> Unit {
  match self.waiters.pop() {
    Some(coro) => coro.wake()
    None => ()
  }
}

///|
/// Create a new backpressure controller
pub fn BackpressureController::new(
  max_concurrent? : Int = 100,
) -> BackpressureController {
  { active: false, max_concurrent, current_count: 0, waiters: [] }
}

///|
/// Check if backpressure is active
pub fn BackpressureController::is_active(self : BackpressureController) -> Bool {
  self.active || self.current_count >= self.max_concurrent
}

///|
/// Manually activate backpressure
pub fn BackpressureController::activate(self : BackpressureController) -> Unit {
  self.active = true
}

///|
/// Manually deactivate backpressure
pub fn BackpressureController::deactivate(
  self : BackpressureController,
) -> Unit {
  self.active = false
  self.wake_all()
}

///|
/// Try to acquire a slot (non-blocking)
pub fn BackpressureController::try_acquire(
  self : BackpressureController,
) -> Bool {
  if self.is_active() {
    false
  } else {
    self.current_count += 1
    true
  }
}

///|
/// Acquire a slot (blocking)
pub async fn BackpressureController::acquire(
  self : BackpressureController,
) -> Unit {
  while self.is_active() {
    self.waiters.push(@coroutine.current_coroutine())
    @coroutine.suspend()
  }
  self.current_count += 1
}

///|
/// Release a slot
pub fn BackpressureController::release(self : BackpressureController) -> Unit {
  if self.current_count > 0 {
    self.current_count -= 1
  }
  if !(self.is_active()) {
    self.wake_one()
  }
}

///|
/// Get current count
pub fn BackpressureController::current(self : BackpressureController) -> Int {
  self.current_count
}

///|
/// Get max concurrent
pub fn BackpressureController::max(self : BackpressureController) -> Int {
  self.max_concurrent
}

///|
/// Set max concurrent (dynamic adjustment)
pub fn BackpressureController::set_max(
  self : BackpressureController,
  max : Int,
) -> Unit {
  self.max_concurrent = max
  // Wake waiters if we now have capacity
  while !(self.is_active()) && self.waiters.length() > 0 {
    self.wake_one()
  }
}

///|
/// Scoped backpressure - automatically release on scope exit
pub struct BackpressureGuard {
  controller : BackpressureController
}

///|
/// Acquire with guard (for use with defer pattern)
pub async fn BackpressureController::acquire_guard(
  self : BackpressureController,
) -> BackpressureGuard {
  self.acquire()
  { controller: self }
}

///|
/// Release the guard
pub fn BackpressureGuard::release(self : BackpressureGuard) -> Unit {
  self.controller.release()
}

///|
/// Execute function with backpressure control
pub async fn[T] BackpressureController::with_backpressure(
  self : BackpressureController,
  f : async () -> T,
) -> T {
  self.acquire()
  try {
    let result = f()
    self.release()
    result
  } catch {
    err => {
      self.release()
      raise err
    }
  }
}
