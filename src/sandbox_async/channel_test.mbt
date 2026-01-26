test "channel: unbounded basic" {
  let (sender, receiver) : (@sandbox_async.Sender[Int], @sandbox_async.Receiver[Int]) = @sandbox_async.new_channel()

  // Try send (non-blocking)
  assert_true(sender.try_send(1))
  assert_true(sender.try_send(2))
  assert_true(sender.try_send(3))

  // Check buffer
  assert_eq(receiver.len(), 3)
  assert_true(receiver.is_ready())

  // Try recv
  assert_eq(receiver.try_recv(), Some(1))
  assert_eq(receiver.try_recv(), Some(2))
  assert_eq(receiver.try_recv(), Some(3))
  assert_eq(receiver.try_recv(), None)
}

test "channel: bounded capacity" {
  let (sender, _receiver) : (@sandbox_async.Sender[Int], @sandbox_async.Receiver[Int]) = @sandbox_async.new_channel_with_capacity(2)

  assert_true(sender.try_send(1))
  assert_true(sender.try_send(2))
  assert_false(sender.try_send(3))  // Buffer full
}

test "channel: close" {
  let (sender, receiver) : (@sandbox_async.Sender[Int], @sandbox_async.Receiver[Int]) = @sandbox_async.new_channel()

  sender.try_send(1) |> ignore
  sender.close()

  assert_true(sender.is_closed())
  // Can still receive buffered data
  assert_eq(receiver.try_recv(), Some(1))
  // Now closed and empty
  assert_true(receiver.is_closed())
}

test "channel: async send recv" {
  @coroutine.run_async_test(async fn() {
    let (sender, receiver) : (@sandbox_async.Sender[Int], @sandbox_async.Receiver[Int]) = @sandbox_async.new_channel()

    // Spawn sender
    let _ = @coroutine.spawn(async fn() {
      sender.send(42) |> ignore
    })

    // Receive
    let value = receiver.recv()
    assert_eq(value, Some(42))
  })
}
