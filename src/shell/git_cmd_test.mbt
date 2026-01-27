// Git command tests for shell

///|
test "git help" {
  let shell = Shell::default()
  let result = shell.exec_line("git")
  assert_eq(result.exit_code, 1)
  assert_true(result.stderr.find("usage: git") is Some(_))
}

///|
test "git init" {
  let shell = Shell::default()
  let result = shell.exec_line("git init")
  assert_eq(result.exit_code, 0)
  assert_true(result.stdout.find("Initialized") is Some(_))
  assert_true(shell.get_ctx().get_fs().exists("/.git"))
  assert_true(shell.get_ctx().get_fs().exists("/.git/HEAD"))
  assert_true(shell.get_ctx().get_fs().exists("/.git/objects"))
  assert_true(shell.get_ctx().get_fs().exists("/.git/refs/heads"))
}

///|
test "git hash-object" {
  let shell = Shell::default()

  // Create a test file
  shell.get_ctx().get_fs().write_string("/test.txt", "hello\n")

  // Hash the file
  let result = shell.exec_line("git hash-object /test.txt")
  assert_eq(result.exit_code, 0)
  // "hello\n" -> ce013625030ba8dba906f756967f9e9ca394464a
  assert_eq(result.stdout, "ce013625030ba8dba906f756967f9e9ca394464a\n")
}

///|
test "git hash-object -w" {
  let shell = Shell::default()

  // Initialize repo first
  ignore(shell.exec_line("git init"))

  // Create and hash a file with -w
  shell.get_ctx().get_fs().write_string("/test.txt", "hello\n")
  let result = shell.exec_line("git hash-object -w /test.txt")
  assert_eq(result.exit_code, 0)
  assert_eq(result.stdout, "ce013625030ba8dba906f756967f9e9ca394464a\n")

  // Verify object was written
  assert_true(shell.get_ctx().get_fs().exists("/.git/objects/ce"))
}

///|
test "git add and write-tree" {
  let shell = Shell::default()

  // Initialize repo
  ignore(shell.exec_line("git init"))

  // Create and add files
  shell.get_ctx().get_fs().write_string("/hello.txt", "hello\n")
  let r1 = shell.exec_line("git add /hello.txt")
  assert_eq(r1.exit_code, 0)

  // Write tree
  let r2 = shell.exec_line("git write-tree")
  assert_eq(r2.exit_code, 0)
  // Tree hash should be 40 chars
  assert_eq(r2.stdout.length(), 41) // 40 + newline
}

///|
test "git commit-tree" {
  let shell = Shell::default()

  // Initialize repo
  ignore(shell.exec_line("git init"))

  // Create and add file
  shell.get_ctx().get_fs().write_string("/hello.txt", "hello\n")
  ignore(shell.exec_line("git add /hello.txt"))

  // Write tree
  let tree_result = shell.exec_line("git write-tree")
  let tree_hash = tree_result.stdout.trim(chars="\n").to_string()

  // Create commit
  let cmd = "git commit-tree \{tree_hash} -m \"Initial commit\""
  let commit_result = shell.exec_line(cmd)
  assert_eq(commit_result.exit_code, 0)
  // Commit hash should be 40 chars
  assert_eq(commit_result.stdout.length(), 41)
}

///|
test "git commit -m" {
  let shell = Shell::default()

  // Initialize repo
  ignore(shell.exec_line("git init"))

  // Create and add file
  shell.get_ctx().get_fs().write_string("/hello.txt", "hello\n")
  ignore(shell.exec_line("git add /hello.txt"))

  // Commit
  let result = shell.exec_line("git commit -m \"Initial commit\"")
  assert_eq(result.exit_code, 0)
  assert_true(result.stdout.find("root-commit") is Some(_))
  assert_true(result.stdout.find("Initial commit") is Some(_))
}

///|
test "git commit without message" {
  let shell = Shell::default()
  ignore(shell.exec_line("git init"))
  shell.get_ctx().get_fs().write_string("/test.txt", "test\n")
  ignore(shell.exec_line("git add /test.txt"))

  let result = shell.exec_line("git commit")
  assert_eq(result.exit_code, 1)
  assert_true(result.stderr.find("message required") is Some(_))
}

///|
test "git commit with nothing staged" {
  let shell = Shell::default()
  ignore(shell.exec_line("git init"))

  let result = shell.exec_line("git commit -m \"Empty\"")
  assert_eq(result.exit_code, 1)
  assert_true(result.stderr.find("nothing to commit") is Some(_))
}

///|
test "git unknown command" {
  let shell = Shell::default()
  let result = shell.exec_line("git unknown")
  assert_eq(result.exit_code, 1)
  assert_true(result.stderr.find("is not a git command") is Some(_))
}

///|
test "git workflow" {
  let shell = Shell::default()

  // Full workflow: init -> add -> write-tree -> commit-tree -> log
  let script =
    #|git init
    #|cd /
  ignore(shell.exec_script(script))

  // Create file
  shell.get_ctx().get_fs().write_string("/README.md", "# Hello\n")

  // Add file
  let r1 = shell.exec_line("git add README.md")
  assert_eq(r1.exit_code, 0)

  // Write tree
  let r2 = shell.exec_line("git write-tree")
  assert_eq(r2.exit_code, 0)
  let tree_hash = r2.stdout.trim(chars="\n").to_string()

  // Create commit
  let r3 = shell.exec_line("git commit-tree \{tree_hash} -m \"Add README\"")
  assert_eq(r3.exit_code, 0)

  // Check log
  let r4 = shell.exec_line("git log")
  assert_eq(r4.exit_code, 0)
  assert_true(r4.stdout.find("commit") is Some(_))
}
