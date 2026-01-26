test "timeout: with_timeout success" {
  @coroutine.run_async_test(async fn() {
    let result = @sandbox_async.with_timeout(1000, async fn() { 42 })
    match result {
      Ok(v) => assert_eq(v, 42)
      Err(_) => panic()
    }
  })
}

test "timeout: TimeoutError" {
  let err = @sandbox_async.TimeoutError("test")
  assert_true(err is @sandbox_async.TimeoutError(_))
}
