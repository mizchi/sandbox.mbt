test "basic file operations" {
  @coroutine.run_async_test(async fn() {
    let ctx = @async.SandboxContext::new()

    // Write file
    ctx.write_text("/test.txt", "hello world")

    // Read file
    let content = ctx.read_text("/test.txt")
    assert_eq(content, "hello world")

    // Check exists
    assert_true(ctx.exists("/test.txt"))
    assert_false(ctx.exists("/nonexistent.txt"))
  })
}

test "directory operations" {
  @coroutine.run_async_test(async fn() {
    let ctx = @async.SandboxContext::new()

    // Create directory
    ctx.mkdir("/mydir")

    // Write file in directory
    ctx.write_text("/mydir/file.txt", "content")

    // Read directory
    let entries = ctx.readdir("/mydir")
    assert_eq(entries.length(), 1)
    assert_eq(entries[0].name, "file.txt")
  })
}

test "environment" {
  let ctx = @async.SandboxContext::new()

  // Default env
  assert_true(ctx.get_env("HOME") is Some(_))

  // Set and get
  ctx.set_env("MY_VAR", "my_value")
  assert_eq(ctx.get_env("MY_VAR"), Some("my_value"))
}

test "cwd operations" {
  @coroutine.run_async_test(async fn() {
    let ctx = @async.SandboxContext::new()

    // Default cwd
    assert_eq(ctx.cwd(), "/")

    // Create and change to directory
    ctx.mkdir("/workdir")
    ctx.chdir("/workdir")
    assert_eq(ctx.cwd(), "/workdir")
  })
}
