/// Waitable - WASI 0.3 waitable/waitable-set compatible abstraction
///
/// Allows waiting on multiple streams/futures simultaneously

///|
/// Waitable trait - anything that can be waited on
pub(open) trait Waitable {
  /// Check if ready without blocking. Returns true if ready.
  is_ready(Self) -> Bool

  /// Get the coroutine to wake when ready (if suspended)
  get_waiter(Self) -> @coroutine.Coroutine?

  /// Set the coroutine to wake when ready
  set_waiter(Self, @coroutine.Coroutine?) -> Unit
}

///|
/// Waitable wrapper for ReadEnd
pub struct WaitableRead {
  reader : ReadEnd
}

///|
/// Waitable wrapper for FutureRead
pub struct WaitableFuture[T] {
  future : FutureRead[T]
}

///|
/// Create waitable from ReadEnd
pub fn ReadEnd::as_waitable(self : ReadEnd) -> WaitableRead {
  { reader: self }
}

///|
/// Create waitable from FutureRead
pub fn[T] FutureRead::as_waitable(self : FutureRead[T]) -> WaitableFuture[T] {
  { future: self }
}

// Implement Waitable for WaitableRead

///|
pub impl Waitable for WaitableRead with is_ready(self) {
  match self.reader.inner.state {
    HasData(_) | Closed => true
    Empty => false
  }
}

///|
pub impl Waitable for WaitableRead with get_waiter(self) {
  self.reader.inner.reader_waiting
}

///|
pub impl Waitable for WaitableRead with set_waiter(self, coro) {
  self.reader.inner.reader_waiting = coro
}

// Implement Waitable for WaitableFuture

///|
pub impl[T] Waitable for WaitableFuture[T] with is_ready(self) {
  !(self.future.inner.state is Pending)
}

///|
pub impl[T] Waitable for WaitableFuture[T] with get_waiter(self) {
  if self.future.inner.waiters.length() > 0 {
    Some(self.future.inner.waiters[0])
  } else {
    None
  }
}

///|
pub impl[T] Waitable for WaitableFuture[T] with set_waiter(self, coro) {
  match coro {
    Some(c) =>
      if !(self.future.inner.waiters.contains(c)) {
        self.future.inner.waiters.push(c)
      }
    None => self.future.inner.waiters.clear()
  }
}

///|
/// Result of wait_any - which waitable became ready
pub(all) enum WaitResult {
  Index(Int) // Index of ready waitable
  Timeout // Timeout occurred (future extension)
}

///|
/// Wait for any of the waitables to become ready
/// Returns the index of the first ready waitable
pub async fn[W : Waitable] wait_any(waitables : Array[W]) -> WaitResult {
  // Check if any is already ready
  for i, w in waitables {
    if w.is_ready() {
      return Index(i)
    }
  }

  // None ready, need to wait
  let current = @coroutine.current_coroutine()

  // Register waiter on all
  for w in waitables {
    w.set_waiter(Some(current))
  }

  // Suspend until one wakes us
  @coroutine.suspend()

  // Find which one is ready
  for i, w in waitables {
    if w.is_ready() {
      // Clean up waiters
      for w2 in waitables {
        w2.set_waiter(None)
      }
      return Index(i)
    }
  }

  // Spurious wakeup, try again
  wait_any(waitables)
}

///|
/// Wait for all waitables to become ready
pub async fn[W : Waitable] wait_all(waitables : Array[W]) -> Unit {
  let remaining : Array[Int] = []
  for i in 0..<waitables.length() {
    remaining.push(i)
  }
  while remaining.length() > 0 {
    // Find next ready
    let mut found = -1
    for i = 0; i < remaining.length(); i = i + 1 {
      if waitables[remaining[i]].is_ready() {
        found = i
        break
      }
    }
    if found >= 0 {
      // Remove from remaining
      let _ = remaining.remove(found)
    } else {
      // Wait for any to become ready
      let current = @coroutine.current_coroutine()
      for idx in remaining {
        waitables[idx].set_waiter(Some(current))
      }
      @coroutine.suspend()

      // Clean up
      for idx in remaining {
        waitables[idx].set_waiter(None)
      }
    }
  }
}

///|
/// Select - wait for first of two different waitable types
pub async fn[A : Waitable, B : Waitable] select2(a : A, b : B) -> (Bool, Bool) {
  // Returns (a_ready, b_ready)
  while true {
    let a_ready = a.is_ready()
    let b_ready = b.is_ready()
    if a_ready || b_ready {
      return (a_ready, b_ready)
    }

    // Wait
    let current = @coroutine.current_coroutine()
    a.set_waiter(Some(current))
    b.set_waiter(Some(current))
    @coroutine.suspend()
    a.set_waiter(None)
    b.set_waiter(None)
  }
  // Unreachable
  (false, false)
}
