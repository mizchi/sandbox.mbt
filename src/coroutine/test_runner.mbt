// Test runner for async tests without moonbitlang/async dependency

///|
/// Run an async function to completion
pub fn run_async_test(f : async () -> Unit) -> Unit raise {
  let coro = spawn(f)
  // Run the scheduler until the coroutine completes
  while !(no_more_work()) {
    reschedule()
  }
  // Check if the coroutine failed
  coro.unwrap()
}
