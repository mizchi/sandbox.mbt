/// Timeout - WASI 0.3 timeout support for waitable operations
///
/// Provides timeout wrappers for async operations

///|
/// Timeout error
pub(all) suberror TimeoutError {
  TimeoutError(String)
}

///|
/// Wait for a waitable with timeout (in milliseconds)
pub async fn[W : Waitable] wait_with_timeout(
  waitable : W,
  timeout_ms : Int,
) -> Result[Unit, TimeoutError] {
  let start = @coroutine.now()
  while true {
    if waitable.is_ready() {
      return Ok(())
    }
    let elapsed = @coroutine.now() - start
    if elapsed >= timeout_ms.to_int64() {
      return Err(TimeoutError("timeout after \{timeout_ms}ms"))
    }

    // Yield control
    @coroutine.pause()
  }

  // Unreachable
  Ok(())
}

///|
/// Wait for any waitable with timeout
pub async fn[W : Waitable] wait_any_timeout(
  waitables : Array[W],
  timeout_ms : Int,
) -> Result[WaitResult, TimeoutError] {
  let start = @coroutine.now()
  while true {
    // Check if any is ready
    for i, w in waitables {
      if w.is_ready() {
        return Ok(Index(i))
      }
    }
    let elapsed = @coroutine.now() - start
    if elapsed >= timeout_ms.to_int64() {
      return Err(TimeoutError("timeout after \{timeout_ms}ms"))
    }
    @coroutine.pause()
  }

  // Unreachable
  Ok(Timeout)
}

///|
/// Run an async function with timeout
pub async fn[T] with_timeout(
  timeout_ms : Int,
  f : async () -> T,
) -> Result[T, TimeoutError] {
  let (reader, writer) = new_future()

  // Spawn the task
  let _ = @coroutine.spawn(async fn() {
    let result = f()
    let _ = writer.resolve(result)

  })

  // Wait with timeout
  let start = @coroutine.now()
  while true {
    if reader.is_done() {
      match reader.poll() {
        Some(Some(v)) => return Ok(v)
        _ => return Err(TimeoutError("task failed"))
      }
    }
    let elapsed = @coroutine.now() - start
    if elapsed >= timeout_ms.to_int64() {
      return Err(TimeoutError("timeout after \{timeout_ms}ms"))
    }
    @coroutine.pause()
  }

  // Unreachable
  Err(TimeoutError("unreachable"))
}
