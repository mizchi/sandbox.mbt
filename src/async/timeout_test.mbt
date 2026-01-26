test "timeout: with_timeout success" {
  @coroutine.run_async_test(async fn() {
    let result = @async.with_timeout(1000, async fn() { 42 })
    match result {
      Ok(v) => assert_eq(v, 42)
      Err(_) => panic()
    }
  })
}

test "timeout: TimeoutError" {
  let err = @async.TimeoutError("test")
  assert_true(err is @async.TimeoutError(_))
}
