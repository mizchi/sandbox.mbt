// Simulated time for sandbox environment

///|
let simulated_time : Ref[Int64] = Ref::new(0L)

///|
/// Get current simulated time in milliseconds
pub fn now() -> Int64 {
  simulated_time.val
}

///|
/// Advance simulated time by the given duration
pub fn advance_time(duration : Int64) -> Unit {
  simulated_time.val = simulated_time.val + duration
}

///|
/// Reset simulated time to zero
pub fn reset_time() -> Unit {
  simulated_time.val = 0L
}

///|
/// Sleep for the given duration (in milliseconds)
/// In sandbox mode, this advances simulated time and yields to other coroutines
pub async fn sleep(duration : Int) -> Unit {
  advance_time(duration.to_int64())
  pause()
}
