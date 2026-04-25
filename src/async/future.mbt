/// Future - WASI 0.3 future<T> compatible single-value channel
///
/// Design notes:
/// - Single value: exactly one value is transferred
/// - Once resolved, the value can be read multiple times
/// - Async await blocks until value is available

///|
/// Future state
pub(all) enum FutureState[T] {
  Pending
  Resolved(T)
  Failed(Error)
}

///|
/// Internal shared state (exposed for Waitable impl)
pub struct FutureInner[T] {
  mut state : FutureState[T]
  waiters : Array[@coroutine.Coroutine]
}

///|
/// Wake all waiting coroutines
fn[T] FutureInner::wake_all(self : FutureInner[T]) -> Unit {
  for coro in self.waiters {
    coro.wake()
  }
  self.waiters.clear()
}

///|
/// Readable end of a Future (for awaiting)
pub struct FutureRead[T] {
  inner : FutureInner[T]
}

///|
/// Writable end of a Future (for resolving)
pub struct FutureWrite[T] {
  inner : FutureInner[T]
}

///|
/// Create a new (readable, writable) future pair
pub fn[T] new_future() -> (FutureRead[T], FutureWrite[T]) {
  let inner : FutureInner[T] = { state: Pending, waiters: [] }
  ({ inner, }, { inner, })
}

///|
/// Await the future value. Blocks until resolved or failed.
pub async fn[T] FutureRead::await_(self : FutureRead[T]) -> T raise Error {
  while true {
    match self.inner.state {
      Resolved(value) => return value
      Failed(err) => raise err
      Pending => {
        self.inner.waiters.push(@coroutine.current_coroutine())
        @coroutine.suspend()
      }
    }
  }
  // Unreachable
  panic()
}

///|
/// Check if the future is resolved without blocking
pub fn[T] FutureRead::poll(self : FutureRead[T]) -> T?? {
  match self.inner.state {
    Resolved(value) => Some(Some(value))
    Failed(_) => Some(None) // Failed, but caller needs to await for error
    Pending => None
  }
}

///|
/// Check if future is pending
pub fn[T] FutureRead::is_pending(self : FutureRead[T]) -> Bool {
  self.inner.state is Pending
}

///|
/// Check if future is resolved (success or failure)
pub fn[T] FutureRead::is_done(self : FutureRead[T]) -> Bool {
  !(self.inner.state is Pending)
}

///|
/// Resolve the future with a value
pub fn[T] FutureWrite::resolve(self : FutureWrite[T], value : T) -> Bool {
  match self.inner.state {
    Pending => {
      self.inner.state = Resolved(value)
      self.inner.wake_all()
      true
    }
    _ => false
  }
}

///|
/// Fail the future with an error
pub fn[T] FutureWrite::fail(self : FutureWrite[T], err : Error) -> Bool {
  match self.inner.state {
    Pending => {
      self.inner.state = Failed(err)
      self.inner.wake_all()
      true
    }
    _ => false
  }
}

///|
/// Check if future is still writable (pending)
pub fn[T] FutureWrite::is_pending(self : FutureWrite[T]) -> Bool {
  self.inner.state is Pending
}
