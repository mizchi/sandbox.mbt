///|
test "future: basic resolve and await" {
  @coroutine.run_async_test(async fn() {
    let (reader, writer) = @async.new_future()

    // Spawn resolver
    let _ = @coroutine.spawn(async fn() {
      let _ = writer.resolve(42)

    })

    // Await
    let value : Int = reader.await_()
    assert_eq(value, 42)
  })
}

///|
test "future: multiple awaiters" {
  @coroutine.run_async_test(async fn() {
    let (reader, writer) = @async.new_future()
    let results : Array[Int] = []

    // Spawn multiple awaiters
    let _ = @coroutine.spawn(async fn() {
      let v : Int = reader.await_()
      results.push(v)
    })
    let _ = @coroutine.spawn(async fn() {
      let v : Int = reader.await_()
      results.push(v)
    })

    // Yield to let awaiters start waiting
    @coroutine.pause()

    // Resolve the future
    let _ = writer.resolve(100)

    // Yield multiple times to let awaiters complete
    @coroutine.pause()
    @coroutine.pause()
    @coroutine.pause()
    assert_eq(results.length(), 2)
    assert_eq(results[0], 100)
    assert_eq(results[1], 100)
  })
}

///|
test "future: poll pending" {
  let (reader, _writer) : (@async.FutureRead[Int], @async.FutureWrite[Int]) = @async.new_future()
  assert_true(reader.is_pending())
  assert_true(reader.poll() is None)
}

///|
test "future: poll resolved" {
  let (reader, writer) : (@async.FutureRead[Int], @async.FutureWrite[Int]) = @async.new_future()
  let _ = writer.resolve(42)
  assert_false(reader.is_pending())
  assert_true(reader.is_done())
  match reader.poll() {
    Some(Some(v)) => assert_eq(v, 42)
    _ => panic()
  }
}

///|
test "future: cannot resolve twice" {
  let (_reader, writer) : (@async.FutureRead[Int], @async.FutureWrite[Int]) = @async.new_future()
  assert_true(writer.resolve(1))
  assert_false(writer.resolve(2)) // Should fail
}
