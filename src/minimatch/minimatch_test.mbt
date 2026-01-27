// Tests for minimatch pattern matching

///|
test "has_glob_chars" {
  assert_true(has_glob_chars("*.txt"))
  assert_true(has_glob_chars("file?.txt"))
  assert_true(has_glob_chars("[abc].txt"))
  assert_false(has_glob_chars("file.txt"))
  assert_false(has_glob_chars("/path/to/file"))
}

///|
test "match: literal" {
  assert_true(match_("hello", "hello"))
  assert_false(match_("hello", "world"))
  assert_false(match_("hello", "hello!"))
  assert_false(match_("hello!", "hello"))
}

///|
test "match: star wildcard" {
  // * matches any number of characters
  assert_true(match_("*", ""))
  assert_true(match_("*", "anything"))
  assert_true(match_("*.txt", "file.txt"))
  assert_true(match_("*.txt", ".txt"))
  assert_false(match_("*.txt", "file.doc"))
  assert_true(match_("file*", "file"))
  assert_true(match_("file*", "file.txt"))
  assert_true(match_("*file*", "myfile.txt"))
  assert_true(match_("a*b*c", "abc"))
  assert_true(match_("a*b*c", "aXXbYYc"))
}

///|
test "match: question mark" {
  // ? matches exactly one character
  assert_true(match_("?", "a"))
  assert_false(match_("?", ""))
  assert_false(match_("?", "ab"))
  assert_true(match_("file?.txt", "file1.txt"))
  assert_true(match_("file?.txt", "fileA.txt"))
  assert_false(match_("file?.txt", "file10.txt"))
  assert_true(match_("???", "abc"))
  assert_false(match_("???", "ab"))
}

///|
test "match: character class" {
  // [abc] matches one of the characters
  assert_true(match_("[abc]", "a"))
  assert_true(match_("[abc]", "b"))
  assert_true(match_("[abc]", "c"))
  assert_false(match_("[abc]", "d"))
  assert_false(match_("[abc]", ""))
  assert_true(match_("file[123].txt", "file1.txt"))
  assert_true(match_("file[123].txt", "file2.txt"))
  assert_false(match_("file[123].txt", "file4.txt"))
}

///|
test "match: character range" {
  // [a-z] matches a range
  assert_true(match_("[a-z]", "a"))
  assert_true(match_("[a-z]", "m"))
  assert_true(match_("[a-z]", "z"))
  assert_false(match_("[a-z]", "A"))
  assert_false(match_("[a-z]", "0"))
  assert_true(match_("[0-9]", "5"))
  assert_false(match_("[0-9]", "a"))
  assert_true(match_("[a-zA-Z]", "X"))
}

///|
test "match: negated character class" {
  // [!abc] or [^abc] matches anything except listed
  assert_false(match_("[!abc]", "a"))
  assert_true(match_("[!abc]", "d"))
  assert_true(match_("[!abc]", "x"))
  assert_false(match_("[^abc]", "b"))
  assert_true(match_("[^abc]", "z"))
  assert_true(match_("[!0-9]", "a"))
  assert_false(match_("[!0-9]", "5"))
}

///|
test "match: combined patterns" {
  assert_true(match_("*.t?t", "file.txt"))
  assert_true(match_("*.t?t", "doc.tnt"))
  assert_false(match_("*.t?t", "file.text"))
  assert_true(match_("[a-z]*.[ch]", "main.c"))
  assert_true(match_("[a-z]*.[ch]", "utils.h"))
  assert_false(match_("[a-z]*.[ch]", "Main.c"))
}

///|
test "filter" {
  let items = ["file.txt", "data.txt", "image.png", "doc.doc"]
  let result = filter("*.txt", items)
  assert_eq(result.length(), 2)
  assert_true(result.contains("file.txt"))
  assert_true(result.contains("data.txt"))
}

///|
test "match_any" {
  assert_true(match_any(["*.txt", "*.doc"], "file.txt"))
  assert_true(match_any(["*.txt", "*.doc"], "file.doc"))
  assert_false(match_any(["*.txt", "*.doc"], "file.png"))
}

///|
test "match_all" {
  assert_true(match_all(["*file*", "*.txt"], "myfile.txt"))
  assert_false(match_all(["*file*", "*.txt"], "myfile.doc"))
  assert_false(match_all(["*file*", "*.txt"], "data.txt"))
}
