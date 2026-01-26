///|
test "shell: basic echo" {
  let shell = Shell::new()
  let result = shell.execute("echo hello world")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "hello world\n")
}

///|
test "shell: mkdir and ls" {
  let shell = Shell::new()

  let r1 = shell.execute("mkdir /testdir")
  assert_eq(r1.exit_code, 0)

  let r2 = shell.execute("ls /")
  assert_eq(r2.exit_code, 0)
  assert_true(r2.stdout.contains("testdir/"))
}

///|
test "shell: file operations" {
  let shell = Shell::new()

  // Create file
  let _ = shell.execute("touch /hello.txt")

  // Write using echo > (not implemented, so use backend directly)
  let backend = shell.get_backend()
  let fd = backend.open("/hello.txt", OpenFlags::write_only())
  let _ = backend.write(fd, b"Hello, Shell!")
  backend.close(fd)

  // Cat file
  let r = shell.execute("cat /hello.txt")
  assert_eq(r.exit_code, 0)
  assert_eq(r.stdout, "Hello, Shell!")
}

///|
test "shell: pwd and cd" {
  let shell = Shell::new()

  let r1 = shell.execute("pwd")
  assert_eq(r1.stdout, "/\n")

  let _ = shell.execute("mkdir /mydir")
  let _ = shell.execute("cd /mydir")

  let r2 = shell.execute("pwd")
  assert_eq(r2.stdout, "/mydir\n")
}

///|
test "shell: help command" {
  let shell = Shell::new()
  let r = shell.execute("help")
  assert_eq(r.exit_code, 0)
  assert_true(r.stdout.contains("echo"))
  assert_true(r.stdout.contains("cat"))
}

///|
test "shell: command not found" {
  let shell = Shell::new()
  let r = shell.execute("nonexistent")
  assert_eq(r.exit_code, 127)
  assert_true(r.stderr.contains("shell:"))
}

///|
test "shell: quoted arguments" {
  let shell = Shell::new()
  let r = shell.execute("echo \"hello world\"")
  assert_eq(r.exit_code, 0)
  assert_eq(r.stdout, "hello world\n")
}

///|
test "shell: script execution" {
  let shell = Shell::new()
  let script =
    #|mkdir /test
    #|touch /test/a.txt
    #|touch /test/b.txt
    #|ls /test
  let results = shell.execute_script(script)

  assert_eq(results.length(), 4)
  assert_eq(results[0].exit_code, 0) // mkdir
  assert_eq(results[1].exit_code, 0) // touch
  assert_eq(results[2].exit_code, 0) // touch
  assert_eq(results[3].exit_code, 0) // ls
  assert_true(results[3].stdout.contains("a.txt"))
  assert_true(results[3].stdout.contains("b.txt"))
}

///|
test "shell: exit command" {
  let shell = Shell::new()

  assert_true(shell.is_running())
  let _ = shell.execute("exit")
  assert_false(shell.is_running())
}

///|
test "shell: grep in pipeline style" {
  let shell = Shell::new()
  let backend = shell.get_backend()

  // Create file with content
  let fd = backend.open("/data.txt", OpenFlags::create())
  let _ = backend.write(fd, b"apple\nbanana\napricot\ncherry")
  backend.close(fd)

  // Grep for 'ap'
  let r = shell.execute("grep ap /data.txt")
  assert_eq(r.exit_code, 0)
  assert_true(r.stdout.contains("apple"))
  assert_true(r.stdout.contains("apricot"))
  assert_false(r.stdout.contains("banana"))
}
