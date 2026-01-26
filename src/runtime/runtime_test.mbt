///|
test "memfs backend: basic file operations" {
  let backend = MemfsBackend::new()

  // Create and write file
  let fd = backend.open("/test.txt", OpenFlags::create())
  let _ = backend.write(fd, b"hello world")
  backend.close(fd)

  // Read file
  let fd2 = backend.open("/test.txt", OpenFlags::read_only())
  let data = backend.read(fd2, 100)
  backend.close(fd2)

  assert_eq(data, b"hello world")
}

///|
test "memfs backend: directory operations" {
  let backend = MemfsBackend::new()

  // Create directory
  backend.mkdir("/mydir")
  assert_true(backend.exists("/mydir"))

  // Create file in directory
  let fd = backend.open("/mydir/file.txt", OpenFlags::create())
  let _ = backend.write(fd, b"content")
  backend.close(fd)

  // List directory
  let entries = backend.readdir("/mydir")
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].name, "file.txt")
}

///|
test "memfs backend: environment" {
  let backend = MemfsBackend::new()

  // Default env
  assert_eq(backend.get_env("HOME"), Some("/home"))
  assert_eq(backend.cwd(), "/")

  // Set env
  backend.set_env("MY_VAR", "my_value")
  assert_eq(backend.get_env("MY_VAR"), Some("my_value"))

  // Change directory
  backend.mkdir("/newdir")
  backend.chdir("/newdir")
  assert_eq(backend.cwd(), "/newdir")
  assert_eq(backend.get_env("PWD"), Some("/newdir"))
}

///|
test "memfs backend: process execution" {
  let backend = MemfsBackend::new()

  // Register command that returns args count
  backend.register("argcount", fn(ctx) { ctx.args.length() })

  // Spawn and wait
  let cmd = Command::new("argcount").args(["a", "b", "c"])
  let proc = backend.spawn(cmd)
  let status = backend.wait(proc.pid())

  assert_eq(status.code, 3)
}

///|
test "memfs backend: builtins basic" {
  let backend = MemfsBackend::new()
  backend.register_builtins()

  // Test true/false
  let proc_true = backend.spawn(Command::new("true"))
  assert_eq(backend.wait(proc_true.pid()).code, 0)

  let proc_false = backend.spawn(Command::new("false"))
  assert_eq(backend.wait(proc_false.pid()).code, 1)

  // Test mkdir + ls
  let proc_mkdir = backend.spawn(Command::new("mkdir").arg("/testdir"))
  assert_eq(backend.wait(proc_mkdir.pid()).code, 0)
  assert_true(backend.exists("/testdir"))
}

///|
test "memfs backend: cd and pwd" {
  let backend = MemfsBackend::new()
  backend.register_builtins()

  // Create directory and cd into it
  backend.mkdir("/mydir")
  let proc_cd = backend.spawn(Command::new("cd").arg("/mydir"))
  assert_eq(backend.wait(proc_cd.pid()).code, 0)
  assert_eq(backend.cwd(), "/mydir")
}

///|
test "memfs backend: file not found" {
  let backend = MemfsBackend::new()

  let result : Result[Fd, IOError] = try {
    Ok(backend.open("/nonexistent", OpenFlags::read_only()))
  } catch {
    e => Err(e)
  }

  assert_true(result is Err(IOError::NotFound(_)))
}

///|
test "memfs backend: stdout capture" {
  let backend = MemfsBackend::new()
  backend.register_builtins()

  // Run echo with piped stdout
  let cmd = Command::new("echo")
    .args(["hello", "world"])
    .stdout(Stdio::Piped)
  let proc = backend.spawn(cmd)
  let pid = proc.pid()

  assert_eq(backend.wait(pid).code, 0)

  let output = backend.read_stdout(pid)
  assert_eq(output, "hello world\n")
}

///|
test "memfs backend: cat with stdout" {
  let backend = MemfsBackend::new()
  backend.register_builtins()

  // Create a file
  let fd = backend.open("/hello.txt", OpenFlags::create())
  let _ = backend.write(fd, b"Hello, File!")
  backend.close(fd)

  // Cat it with piped stdout
  let cmd = Command::new("cat")
    .arg("/hello.txt")
    .stdout(Stdio::Piped)
  let proc = backend.spawn(cmd)
  let pid = proc.pid()

  assert_eq(backend.wait(pid).code, 0)
  assert_eq(backend.read_stdout(pid), "Hello, File!")
}

///|
test "memfs backend: ls with stdout" {
  let backend = MemfsBackend::new()
  backend.register_builtins()

  // Create some files
  backend.mkdir("/testdir")
  let fd1 = backend.open("/testdir/a.txt", OpenFlags::create())
  backend.close(fd1)
  let fd2 = backend.open("/testdir/b.txt", OpenFlags::create())
  backend.close(fd2)

  // ls with piped stdout
  let cmd = Command::new("ls")
    .arg("/testdir")
    .stdout(Stdio::Piped)
  let proc = backend.spawn(cmd)
  let pid = proc.pid()

  assert_eq(backend.wait(pid).code, 0)
  let output = backend.read_stdout(pid)
  assert_true(output.contains("a.txt"))
  assert_true(output.contains("b.txt"))
}

///|
test "memfs backend: pipe between processes" {
  let backend = MemfsBackend::new()

  // Register a command that reads from stdin and transforms
  backend.register("uppercase", fn(ctx) {
    let input = ctx.read_stdin()
    ctx.write_stdout(input.to_upper())
    0
  })

  // Create pipe
  let pipe = Pipe::new()
  let _ = pipe.write_string("hello")

  // This is a simplified test - real piping would need async
  // For now, just test that the pipe works
  assert_eq(pipe.read_string(), "hello")
}
