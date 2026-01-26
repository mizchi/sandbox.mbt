// Simple sync test first
test "byte stream: sync write then read" {
  let (reader, writer) = @async.new_byte_stream()

  // Check initial state
  assert_true(reader.poll() is None)

  // Can't do sync write since write is async, but we can check state sharing
  // by checking if close propagates
  writer.close()
  assert_true(reader.is_closed())
}

test "byte stream: basic read/write" {
  @coroutine.run_async_test(async fn() {
    let (reader, writer) = @async.new_byte_stream()

    // Spawn writer
    let _ = @coroutine.spawn(async fn() {
      let _ = writer.write(b"hello")
      writer.close()
    })

    // Give writer a chance to run
    @coroutine.pause()

    // Check if data is there
    match reader.poll() {
      Some(data) => {
        assert_eq(data, b"hello")
      }
      None => {
        // Data not ready, try read (which should block)
        let data = reader.read()
        assert_eq(data, b"hello")
      }
    }
  })
}

test "byte stream: multiple writes" {
  @coroutine.run_async_test(async fn() {
    let (reader, writer) = @async.new_byte_stream()

    let _ = @coroutine.spawn(async fn() {
      let _ = writer.write(b"one")
      let _ = writer.write(b"two")
      let _ = writer.write(b"three")
      writer.close()
    })

    // Interleave reads with yields
    @coroutine.pause()
    let d1 = reader.read()
    @coroutine.pause()
    let d2 = reader.read()
    @coroutine.pause()
    let d3 = reader.read()

    assert_eq(d1, b"one")
    assert_eq(d2, b"two")
    assert_eq(d3, b"three")
  })
}

test "byte stream: poll without blocking" {
  @coroutine.run_async_test(async fn() {
    let (reader, writer) = @async.new_byte_stream()

    // Poll empty stream
    assert_true(reader.poll() is None)

    // Write data
    let _ = @coroutine.spawn(async fn() {
      let _ = writer.write(b"data")
    })

    // Need to yield to let writer run
    @coroutine.pause()

    // Now poll should return data
    match reader.poll() {
      Some(data) => assert_eq(data, b"data")
      None => panic()
    }
  })
}

test "byte stream: is_closed" {
  let (reader, writer) = @async.new_byte_stream()

  assert_false(reader.is_closed())
  assert_false(writer.is_closed())

  writer.close()

  assert_true(reader.is_closed())
  assert_true(writer.is_closed())
}
