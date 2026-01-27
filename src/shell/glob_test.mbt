// Tests for glob pattern matching and expansion

///|
test "has_glob_chars" {
  assert_true(has_glob_chars("*.txt"))
  assert_true(has_glob_chars("file?.txt"))
  assert_true(has_glob_chars("[abc].txt"))
  assert_false(has_glob_chars("file.txt"))
  assert_false(has_glob_chars("/path/to/file"))
}

///|
test "glob_match: literal" {
  assert_true(glob_match("hello", "hello"))
  assert_false(glob_match("hello", "world"))
  assert_false(glob_match("hello", "hello!"))
  assert_false(glob_match("hello!", "hello"))
}

///|
test "glob_match: star wildcard" {
  // * matches any number of characters
  assert_true(glob_match("*", ""))
  assert_true(glob_match("*", "anything"))
  assert_true(glob_match("*.txt", "file.txt"))
  assert_true(glob_match("*.txt", ".txt"))
  assert_false(glob_match("*.txt", "file.doc"))
  assert_true(glob_match("file*", "file"))
  assert_true(glob_match("file*", "file.txt"))
  assert_true(glob_match("*file*", "myfile.txt"))
  assert_true(glob_match("a*b*c", "abc"))
  assert_true(glob_match("a*b*c", "aXXbYYc"))
}

///|
test "glob_match: question mark" {
  // ? matches exactly one character
  assert_true(glob_match("?", "a"))
  assert_false(glob_match("?", ""))
  assert_false(glob_match("?", "ab"))
  assert_true(glob_match("file?.txt", "file1.txt"))
  assert_true(glob_match("file?.txt", "fileA.txt"))
  assert_false(glob_match("file?.txt", "file10.txt"))
  assert_true(glob_match("???", "abc"))
  assert_false(glob_match("???", "ab"))
}

///|
test "glob_match: character class" {
  // [abc] matches one of the characters
  assert_true(glob_match("[abc]", "a"))
  assert_true(glob_match("[abc]", "b"))
  assert_true(glob_match("[abc]", "c"))
  assert_false(glob_match("[abc]", "d"))
  assert_false(glob_match("[abc]", ""))
  assert_true(glob_match("file[123].txt", "file1.txt"))
  assert_true(glob_match("file[123].txt", "file2.txt"))
  assert_false(glob_match("file[123].txt", "file4.txt"))
}

///|
test "glob_match: character range" {
  // [a-z] matches a range
  assert_true(glob_match("[a-z]", "a"))
  assert_true(glob_match("[a-z]", "m"))
  assert_true(glob_match("[a-z]", "z"))
  assert_false(glob_match("[a-z]", "A"))
  assert_false(glob_match("[a-z]", "0"))
  assert_true(glob_match("[0-9]", "5"))
  assert_false(glob_match("[0-9]", "a"))
  assert_true(glob_match("[a-zA-Z]", "X"))
}

///|
test "glob_match: negated character class" {
  // [!abc] or [^abc] matches anything except listed
  assert_false(glob_match("[!abc]", "a"))
  assert_true(glob_match("[!abc]", "d"))
  assert_true(glob_match("[!abc]", "x"))
  assert_false(glob_match("[^abc]", "b"))
  assert_true(glob_match("[^abc]", "z"))
  assert_true(glob_match("[!0-9]", "a"))
  assert_false(glob_match("[!0-9]", "5"))
}

///|
test "glob_match: combined patterns" {
  assert_true(glob_match("*.t?t", "file.txt"))
  assert_true(glob_match("*.t?t", "doc.tnt"))
  assert_false(glob_match("*.t?t", "file.text"))
  assert_true(glob_match("[a-z]*.[ch]", "main.c"))
  assert_true(glob_match("[a-z]*.[ch]", "utils.h"))
  assert_false(glob_match("[a-z]*.[ch]", "Main.c"))
}

///|
test "expand_glob: no glob chars" {
  let fs = @fs.Fs::new()
  let results = expand_glob("/file.txt", fs, "/")
  assert_eq(results, ["/file.txt"])
}

///|
test "expand_glob: star in current directory" {
  let fs = @fs.Fs::new()
  fs.write_string("/file1.txt", "1") |> ignore
  fs.write_string("/file2.txt", "2") |> ignore
  fs.write_string("/other.doc", "3") |> ignore

  let results = expand_glob("*.txt", fs, "/")
  assert_eq(results.length(), 2)
  assert_true(results.contains("/file1.txt"))
  assert_true(results.contains("/file2.txt"))
}

///|
test "expand_glob: star with subdirectory" {
  let fs = @fs.Fs::new()
  fs.mkdir_p("/dir") |> ignore
  fs.write_string("/dir/a.txt", "a") |> ignore
  fs.write_string("/dir/b.txt", "b") |> ignore
  fs.write_string("/dir/c.doc", "c") |> ignore

  let results = expand_glob("/dir/*.txt", fs, "/")
  assert_eq(results.length(), 2)
  assert_true(results.contains("/dir/a.txt"))
  assert_true(results.contains("/dir/b.txt"))
}

///|
test "expand_glob: question mark" {
  let fs = @fs.Fs::new()
  fs.write_string("/file1.txt", "1") |> ignore
  fs.write_string("/file2.txt", "2") |> ignore
  fs.write_string("/file10.txt", "10") |> ignore

  let results = expand_glob("/file?.txt", fs, "/")
  assert_eq(results.length(), 2)
  assert_true(results.contains("/file1.txt"))
  assert_true(results.contains("/file2.txt"))
  assert_false(results.contains("/file10.txt"))
}

///|
test "expand_glob: character class" {
  let fs = @fs.Fs::new()
  fs.write_string("/a.txt", "a") |> ignore
  fs.write_string("/b.txt", "b") |> ignore
  fs.write_string("/c.txt", "c") |> ignore
  fs.write_string("/d.txt", "d") |> ignore

  let results = expand_glob("/[abc].txt", fs, "/")
  assert_eq(results.length(), 3)
  assert_true(results.contains("/a.txt"))
  assert_true(results.contains("/b.txt"))
  assert_true(results.contains("/c.txt"))
  assert_false(results.contains("/d.txt"))
}

///|
test "expand_glob: no matches returns pattern" {
  let fs = @fs.Fs::new()
  let results = expand_glob("*.xyz", fs, "/")
  assert_eq(results, ["*.xyz"])
}

///|
test "expand_glob: hidden files skipped" {
  let fs = @fs.Fs::new()
  fs.write_string("/.hidden", "h") |> ignore
  fs.write_string("/visible", "v") |> ignore

  let results = expand_glob("/*", fs, "/")
  assert_eq(results.length(), 1)
  assert_true(results.contains("/visible"))
  assert_false(results.contains("/.hidden"))
}

///|
test "expand_glob: hidden files with dot pattern" {
  let fs = @fs.Fs::new()
  fs.write_string("/.hidden", "h") |> ignore
  fs.write_string("/.other", "o") |> ignore
  fs.write_string("/visible", "v") |> ignore

  let results = expand_glob("/.*", fs, "/")
  assert_eq(results.length(), 2)
  assert_true(results.contains("/.hidden"))
  assert_true(results.contains("/.other"))
}

///|
test "shell glob expansion" {
  let ctx = @posix.PosixContext::default()
  ctx.get_fs().write_string("/a.txt", "a") |> ignore
  ctx.get_fs().write_string("/b.txt", "b") |> ignore
  ctx.get_fs().write_string("/c.doc", "c") |> ignore

  let shell = Shell::new(ctx)
  let result = shell.exec_line("echo *.txt")
  // Should expand and echo the file names
  assert_true(result.stdout.contains("a.txt"))
  assert_true(result.stdout.contains("b.txt"))
  assert_false(result.stdout.contains("c.doc"))
}

///|
test "shell glob with ls" {
  let ctx = @posix.PosixContext::default()
  ctx.get_fs().mkdir_p("/mydir") |> ignore
  ctx.get_fs().write_string("/mydir/file1.txt", "1") |> ignore
  ctx.get_fs().write_string("/mydir/file2.txt", "2") |> ignore
  ctx.get_fs().write_string("/mydir/other.doc", "3") |> ignore

  let shell = Shell::new(ctx)
  let result = shell.exec_line("ls /mydir/*.txt")
  assert_eq(result.exit_code, 0)
  assert_true(result.stdout.contains("file1.txt"))
  assert_true(result.stdout.contains("file2.txt"))
  assert_false(result.stdout.contains("other.doc"))
}

///|
test "shell glob quoted not expanded" {
  let ctx = @posix.PosixContext::default()
  ctx.get_fs().write_string("/a.txt", "a") |> ignore
  ctx.get_fs().write_string("/b.txt", "b") |> ignore

  let shell = Shell::new(ctx)
  let result = shell.exec_line("echo \"*.txt\"")
  // Quoted glob should not be expanded
  assert_eq(result.stdout, "*.txt\n")
}
