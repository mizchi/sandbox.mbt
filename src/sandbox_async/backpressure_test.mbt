test "backpressure: basic acquire/release" {
  let bp = @sandbox_async.BackpressureController::new(max_concurrent=2)

  assert_false(bp.is_active())
  assert_eq(bp.current(), 0)

  // Acquire slots
  assert_true(bp.try_acquire())
  assert_eq(bp.current(), 1)

  assert_true(bp.try_acquire())
  assert_eq(bp.current(), 2)

  // Now at max, should be active
  assert_true(bp.is_active())
  assert_false(bp.try_acquire())

  // Release one
  bp.release()
  assert_eq(bp.current(), 1)
  assert_false(bp.is_active())
}

test "backpressure: manual activate/deactivate" {
  let bp = @sandbox_async.BackpressureController::new()

  assert_false(bp.is_active())

  bp.activate()
  assert_true(bp.is_active())
  assert_false(bp.try_acquire())

  bp.deactivate()
  assert_false(bp.is_active())
  assert_true(bp.try_acquire())
}

test "backpressure: dynamic max adjustment" {
  let bp = @sandbox_async.BackpressureController::new(max_concurrent=1)

  assert_true(bp.try_acquire())
  assert_true(bp.is_active())  // At max

  bp.set_max(2)
  assert_false(bp.is_active())  // Now have room

  assert_true(bp.try_acquire())
  assert_true(bp.is_active())  // At new max
}
