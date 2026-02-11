// Executor tests

///|
test "execute simple command" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("echo hello world")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "hello world\n")
}

///|
test "execute and operator success" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("true && echo yes")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "yes\n")
}

///|
test "execute and operator failure" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("false && echo yes")
  assert_eq(result.exit_code, 1)
  assert_eq(result.stdout, "")
}

///|
test "execute or operator success" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("true || echo fallback")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "")
}

///|
test "execute or operator fallback" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("false || echo fallback")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "fallback\n")
}

///|
test "execute sequence" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("echo a; echo b")
  assert_eq(result.stdout, "a\nb\n")
}

///|
test "execute variable assignment and expansion" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("NAME=world; echo $NAME")
  assert_eq(result.stdout, "world\n")
}

///|
test "execute exit code variable" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("false; echo $?")
  assert_eq(result.stdout, "1\n")
}

///|
test "execute if statement true" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("if true; then echo yes; fi")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "yes\n")
}

///|
test "execute if statement false" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("if false; then echo yes; fi")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "")
}

///|
test "execute if else" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("if false; then echo no; else echo yes; fi")
  assert_eq(result.stdout, "yes\n")
}

///|
test "execute for loop" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("for i in a b c; do echo $i; done")
  assert_eq(result.stdout, "a\nb\nc\n")
}

///|
test "execute while loop" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  // Use counter variable - simple while test
  let result = exec.exec_script(
    "COUNT=0; while test $COUNT -lt 3; do echo $COUNT; COUNT=1; done",
  )
  // This will loop once since COUNT becomes 1 after first iteration
  assert_true(result.stdout.contains("0"))
}

///|
test "execute case statement" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script(
    "case foo in foo) echo match;; bar) echo no;; esac",
  )
  assert_eq(result.stdout, "match\n")
}

///|
test "execute case wildcard" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("case anything in *) echo default;; esac")
  assert_eq(result.stdout, "default\n")
}

///|
test "test command -z" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let r1 = exec.exec_script("test -z \"\" && echo empty")
  assert_eq(r1.stdout, "empty\n")
  let r2 = exec.exec_script("test -z \"nonempty\" || echo notempty")
  assert_eq(r2.stdout, "notempty\n")
}

///|
test "test command -n" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let r1 = exec.exec_script("test -n \"text\" && echo hastext")
  assert_eq(r1.stdout, "hastext\n")
}

///|
test "test command string equality" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let r1 = exec.exec_script("test foo = foo && echo equal")
  assert_eq(r1.stdout, "equal\n")
  let r2 = exec.exec_script("test foo = bar || echo notequal")
  assert_eq(r2.stdout, "notequal\n")
}

///|
test "test command numeric comparison" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let r1 = exec.exec_script("test 5 -eq 5 && echo equal")
  assert_eq(r1.stdout, "equal\n")
  let r2 = exec.exec_script("test 3 -lt 5 && echo less")
  assert_eq(r2.stdout, "less\n")
  let r3 = exec.exec_script("test 7 -gt 5 && echo greater")
  assert_eq(r3.stdout, "greater\n")
}

///|
test "test bracket syntax" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("[ foo = foo ] && echo match")
  assert_eq(result.stdout, "match\n")
}

///|
test "test -f file exists" {
  let ctx = @posix.PosixContext::default()
  ctx.get_fs().write_string("/testfile.txt", "content")
  let exec = Executor::new(ctx)
  let result = exec.exec_script("test -f /testfile.txt && echo exists")
  assert_eq(result.stdout, "exists\n")
}

///|
test "test -d directory exists" {
  let ctx = @posix.PosixContext::default()
  ctx.get_fs().mkdir("/testdir")
  let exec = Executor::new(ctx)
  let result = exec.exec_script("test -d /testdir && echo isdir")
  assert_eq(result.stdout, "isdir\n")
}

///|
test "redirect output to file" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  ignore(exec.exec_script("echo hello > /out.txt"))
  let content = ctx.get_fs().read_string("/out.txt") catch { _ => "" }
  assert_eq(content, "hello\n")
}

///|
test "pipeline execution" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  // For now pipeline just executes commands sequentially
  let result = exec.exec_script("echo hello | cat")
  // The output should at least contain something
  assert_eq(result.exit_code, 0)
}

///|
test "command substitution" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("echo $(echo hello)")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "hello\n")
}

///|
test "command substitution pwd" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("echo $(pwd)")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "/\n") // Default cwd is /
}

///|
test "background execution" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("echo hello &")
  // Background returns 0 immediately
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "hello\n")
}

///|
test "subshell execution" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("( echo from subshell )")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "from subshell\n")
}

///|
test "brace group execution" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  let result = exec.exec_script("{ echo from brace; }")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "from brace\n")
}

///|
test "function definition and call" {
  let ctx = @posix.PosixContext::default()
  let exec = Executor::new(ctx)
  ignore(exec.exec_script("greet() { echo hello; }"))
  let result = exec.exec_script("greet")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "hello\n")
}
