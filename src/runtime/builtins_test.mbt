///|
test "builtin: head" {
  let backend = MemfsBackend::new()
  backend.register_builtins()

  // Create file with multiple lines
  let fd = backend.open("/test.txt", OpenFlags::create())
  let _ = backend.write(fd, b"line1\nline2\nline3\nline4\nline5")
  backend.close(fd)

  // head -n 2
  let cmd = Command::new("head")
    .args(["-n", "2", "/test.txt"])
    .stdout(Stdio::Piped)
  let proc = backend.spawn(cmd)
  assert_eq(backend.wait(proc.pid()).code, 0)

  let output = backend.read_stdout(proc.pid())
  assert_true(output.contains("line1"))
  assert_true(output.contains("line2"))
  assert_false(output.contains("line3"))
}

///|
test "builtin: tail" {
  let backend = MemfsBackend::new()
  backend.register_builtins()

  // Create file with multiple lines
  let fd = backend.open("/test.txt", OpenFlags::create())
  let _ = backend.write(fd, b"line1\nline2\nline3\nline4\nline5")
  backend.close(fd)

  // tail -n 2
  let cmd = Command::new("tail")
    .args(["-n", "2", "/test.txt"])
    .stdout(Stdio::Piped)
  let proc = backend.spawn(cmd)
  assert_eq(backend.wait(proc.pid()).code, 0)

  let output = backend.read_stdout(proc.pid())
  assert_false(output.contains("line3"))
  assert_true(output.contains("line4"))
  assert_true(output.contains("line5"))
}

///|
test "builtin: grep" {
  let backend = MemfsBackend::new()
  backend.register_builtins()

  // Create file
  let fd = backend.open("/test.txt", OpenFlags::create())
  let _ = backend.write(fd, b"hello world\nfoo bar\nhello again")
  backend.close(fd)

  // grep hello
  let cmd = Command::new("grep")
    .args(["hello", "/test.txt"])
    .stdout(Stdio::Piped)
  let proc = backend.spawn(cmd)
  assert_eq(backend.wait(proc.pid()).code, 0)

  let output = backend.read_stdout(proc.pid())
  assert_true(output.contains("hello world"))
  assert_true(output.contains("hello again"))
  assert_false(output.contains("foo bar"))
}

///|
test "builtin: grep not found" {
  let backend = MemfsBackend::new()
  backend.register_builtins()

  let fd = backend.open("/test.txt", OpenFlags::create())
  let _ = backend.write(fd, b"hello world")
  backend.close(fd)

  // grep for non-existent pattern
  let cmd = Command::new("grep")
    .args(["notfound", "/test.txt"])
    .stdout(Stdio::Piped)
  let proc = backend.spawn(cmd)

  // grep returns 1 when no matches
  assert_eq(backend.wait(proc.pid()).code, 1)
}

///|
test "builtin: wc" {
  let backend = MemfsBackend::new()
  backend.register_builtins()

  let fd = backend.open("/test.txt", OpenFlags::create())
  let _ = backend.write(fd, b"hello world\nfoo bar")
  backend.close(fd)

  let cmd = Command::new("wc")
    .arg("/test.txt")
    .stdout(Stdio::Piped)
  let proc = backend.spawn(cmd)
  assert_eq(backend.wait(proc.pid()).code, 0)

  let output = backend.read_stdout(proc.pid())
  // Should contain line count, word count, byte count
  assert_true(output.contains("2")) // 2 lines
}

///|
test "builtin: touch and cp" {
  let backend = MemfsBackend::new()
  backend.register_builtins()

  // touch creates file
  let proc1 = backend.spawn(Command::new("touch").arg("/newfile.txt"))
  assert_eq(backend.wait(proc1.pid()).code, 0)
  assert_true(backend.exists("/newfile.txt"))

  // Write content
  let fd = backend.open("/newfile.txt", OpenFlags::write_only())
  let _ = backend.write(fd, b"content")
  backend.close(fd)

  // cp copies file
  let proc2 = backend.spawn(Command::new("cp").args(["/newfile.txt", "/copy.txt"]))
  assert_eq(backend.wait(proc2.pid()).code, 0)
  assert_true(backend.exists("/copy.txt"))

  // Verify content
  let fd2 = backend.open("/copy.txt", OpenFlags::read_only())
  let data = backend.read(fd2, 100)
  backend.close(fd2)
  assert_eq(data, b"content")
}

///|
test "builtin: mv" {
  let backend = MemfsBackend::new()
  backend.register_builtins()

  // Create file
  let fd = backend.open("/original.txt", OpenFlags::create())
  let _ = backend.write(fd, b"data")
  backend.close(fd)

  // mv renames file
  let proc = backend.spawn(Command::new("mv").args(["/original.txt", "/renamed.txt"]))
  assert_eq(backend.wait(proc.pid()).code, 0)

  assert_false(backend.exists("/original.txt"))
  assert_true(backend.exists("/renamed.txt"))
}
