// Lexer tests

///|
test "tokenize simple command" {
  let tokens = tokenize("echo hello world")
  assert_eq(tokens.length(), 4)
  assert_eq(tokens[0], Token::Word("echo"))
  assert_eq(tokens[1], Token::Word("hello"))
  assert_eq(tokens[2], Token::Word("world"))
  assert_eq(tokens[3], Token::EOF)
}

///|
test "tokenize pipe" {
  let tokens = tokenize("cat file | grep pattern")
  assert_eq(tokens[0], Token::Word("cat"))
  assert_eq(tokens[1], Token::Word("file"))
  assert_eq(tokens[2], Token::Pipe)
  assert_eq(tokens[3], Token::Word("grep"))
  assert_eq(tokens[4], Token::Word("pattern"))
}

///|
test "tokenize and operator" {
  let tokens = tokenize("true && echo yes")
  assert_eq(tokens[0], Token::Word("true"))
  assert_eq(tokens[1], Token::And)
  assert_eq(tokens[2], Token::Word("echo"))
  assert_eq(tokens[3], Token::Word("yes"))
}

///|
test "tokenize or operator" {
  let tokens = tokenize("false || echo fallback")
  assert_eq(tokens[0], Token::Word("false"))
  assert_eq(tokens[1], Token::Or)
  assert_eq(tokens[2], Token::Word("echo"))
  assert_eq(tokens[3], Token::Word("fallback"))
}

///|
test "tokenize semicolon" {
  let tokens = tokenize("echo a; echo b")
  assert_eq(tokens[0], Token::Word("echo"))
  assert_eq(tokens[1], Token::Word("a"))
  assert_eq(tokens[2], Token::Semi)
  assert_eq(tokens[3], Token::Word("echo"))
  assert_eq(tokens[4], Token::Word("b"))
}

///|
test "tokenize redirects" {
  let tokens = tokenize("echo hello > file.txt")
  assert_eq(tokens[0], Token::Word("echo"))
  assert_eq(tokens[1], Token::Word("hello"))
  assert_eq(tokens[2], Token::RedirectOut)
  assert_eq(tokens[3], Token::Word("file.txt"))
}

///|
test "tokenize redirect append" {
  let tokens = tokenize("echo hello >> file.txt")
  assert_eq(tokens[2], Token::RedirectAppend)
}

///|
test "tokenize redirect stderr" {
  let tokens = tokenize("cmd 2> err.log")
  assert_eq(tokens[0], Token::Word("cmd"))
  assert_eq(tokens[1], Token::RedirectErr)
  assert_eq(tokens[2], Token::Word("err.log"))
}

///|
test "tokenize variable" {
  let tokens = tokenize("echo $NAME")
  assert_eq(tokens[0], Token::Word("echo"))
  assert_eq(tokens[1], Token::Variable("NAME"))
}

///|
test "tokenize variable braces" {
  let tokens = tokenize("echo ${VAR}")
  assert_eq(tokens[1], Token::Variable("VAR"))
}

///|
test "tokenize exit code" {
  let tokens = tokenize("echo $?")
  assert_eq(tokens[1], Token::ExitCode)
}

///|
test "tokenize positional args" {
  let tokens = tokenize("echo $0 $1 $9")
  assert_eq(tokens[1], Token::ArgN(0))
  assert_eq(tokens[2], Token::ArgN(1))
  assert_eq(tokens[3], Token::ArgN(9))
}

///|
test "tokenize assignment" {
  let tokens = tokenize("NAME=value")
  assert_eq(tokens[0], Token::Assignment("NAME", "value"))
}

///|
test "tokenize if statement keywords" {
  let tokens = tokenize("if true; then echo yes; fi")
  assert_eq(tokens[0], Token::If)
  assert_eq(tokens[1], Token::Word("true"))
  assert_eq(tokens[2], Token::Semi)
  assert_eq(tokens[3], Token::Then)
  assert_eq(tokens[4], Token::Word("echo"))
  assert_eq(tokens[5], Token::Word("yes"))
  assert_eq(tokens[6], Token::Semi)
  assert_eq(tokens[7], Token::Fi)
}

///|
test "tokenize for loop keywords" {
  let tokens = tokenize("for i in a b c; do echo $i; done")
  assert_eq(tokens[0], Token::For)
  assert_eq(tokens[1], Token::Word("i"))
  assert_eq(tokens[2], Token::In)
  assert_eq(tokens[3], Token::Word("a"))
  assert_eq(tokens[4], Token::Word("b"))
  assert_eq(tokens[5], Token::Word("c"))
  assert_eq(tokens[6], Token::Semi)
  assert_eq(tokens[7], Token::Do)
}

///|
test "tokenize while loop keywords" {
  let tokens = tokenize("while true; do echo x; done")
  assert_eq(tokens[0], Token::While)
  assert_eq(tokens[1], Token::Word("true"))
  assert_eq(tokens[2], Token::Semi)
  assert_eq(tokens[3], Token::Do)
}

///|
test "tokenize case keywords" {
  let tokens = tokenize("case x in a) echo a;; esac")
  assert_eq(tokens[0], Token::Case)
  assert_eq(tokens[1], Token::Word("x"))
  assert_eq(tokens[2], Token::In)
  assert_eq(tokens[3], Token::Word("a"))
  assert_eq(tokens[4], Token::RightParen)
  assert_eq(tokens[5], Token::Word("echo"))
  assert_eq(tokens[6], Token::Word("a"))
  assert_eq(tokens[7], Token::DoubleSemi)
  assert_eq(tokens[8], Token::Esac)
}

///|
test "tokenize brackets" {
  let tokens = tokenize("[ -f file ]")
  assert_eq(tokens[0], Token::LeftBracket)
  assert_eq(tokens[1], Token::Word("-f"))
  assert_eq(tokens[2], Token::Word("file"))
  assert_eq(tokens[3], Token::RightBracket)
}

///|
test "tokenize single quoted" {
  let tokens = tokenize("echo 'hello world'")
  assert_eq(tokens[0], Token::Word("echo"))
  assert_eq(tokens[1], Token::Word("hello world"))
}

///|
test "tokenize double quoted" {
  let tokens = tokenize("echo \"hello world\"")
  assert_eq(tokens[0], Token::Word("echo"))
  assert_eq(tokens[1], Token::Word("hello world"))
}

///|
test "tokenize comment" {
  let tokens = tokenize("echo hello # this is comment")
  assert_eq(tokens.length(), 3) // echo, hello, EOF
  assert_eq(tokens[0], Token::Word("echo"))
  assert_eq(tokens[1], Token::Word("hello"))
  assert_eq(tokens[2], Token::EOF)
}

///|
test "tokenize newline" {
  let tokens = tokenize("echo a\necho b")
  assert_eq(tokens[0], Token::Word("echo"))
  assert_eq(tokens[1], Token::Word("a"))
  assert_eq(tokens[2], Token::Newline)
  assert_eq(tokens[3], Token::Word("echo"))
  assert_eq(tokens[4], Token::Word("b"))
}

///|
test "tokenize elif else" {
  let tokens = tokenize("if a; then b; elif c; then d; else e; fi")
  // if(0) a(1) ;(2) then(3) b(4) ;(5) elif(6) c(7) ;(8) then(9) d(10) ;(11) else(12) e(13) ;(14) fi(15) EOF(16)
  assert_eq(tokens[0], Token::If)
  assert_eq(tokens[6], Token::Elif)
  assert_eq(tokens[12], Token::Else)
  assert_eq(tokens[15], Token::Fi)
}

///|
test "tokenize until" {
  let tokens = tokenize("until false; do echo x; done")
  assert_eq(tokens[0], Token::Until)
}

///|
test "keyword in argument position stays as word" {
  // "if" as argument should not be keyword
  let tokens = tokenize("echo if")
  assert_eq(tokens[0], Token::Word("echo"))
  assert_eq(tokens[1], Token::Word("if"))
}
