test "waitable: is_ready checks" {
  let (reader, writer) = @async.new_byte_stream()
  let w = reader.as_waitable()

  // Initially not ready
  assert_false(w.is_ready())

  // After close, ready
  writer.close()
  assert_true(w.is_ready())
}

test "waitable: future is_ready" {
  let (reader, writer) : (@async.FutureRead[Int], @async.FutureWrite[Int]) = @async.new_future()
  let w = reader.as_waitable()

  assert_false(w.is_ready())

  let _ = writer.resolve(42)
  assert_true(w.is_ready())
}
