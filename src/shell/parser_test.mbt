// Parser tests

///|
test "parse simple command" {
  let ast = parse("echo hello world") catch { e => fail("Parse error: \{e}") }
  match ast {
    SimpleCommand(words, _) => {
      assert_eq(words.length(), 3)
      assert_eq(words[0], Literal("echo"))
      assert_eq(words[1], Literal("hello"))
      assert_eq(words[2], Literal("world"))
    }
    _ => fail("Expected SimpleCommand")
  }
}

///|
test "parse pipeline" {
  let ast = parse("echo hello | cat") catch { e => fail("Parse error: \{e}") }
  match ast {
    Pipeline(cmds) => assert_eq(cmds.length(), 2)
    _ => fail("Expected Pipeline")
  }
}

///|
test "parse and operator" {
  let ast = parse("true && echo yes") catch { e => fail("Parse error: \{e}") }
  match ast {
    AndList(_, _) => ()
    _ => fail("Expected AndList")
  }
}

///|
test "parse or operator" {
  let ast = parse("false || echo fallback") catch {
    e => fail("Parse error: \{e}")
  }
  match ast {
    OrList(_, _) => ()
    _ => fail("Expected OrList")
  }
}

///|
test "parse sequence" {
  let ast = parse("echo a; echo b") catch { e => fail("Parse error: \{e}") }
  match ast {
    Sequence(_, _) => ()
    _ => fail("Expected Sequence")
  }
}

///|
test "parse redirect out" {
  let ast = parse("echo hello > file.txt") catch {
    e => fail("Parse error: \{e}")
  }
  match ast {
    SimpleCommand(words, redirects) => {
      assert_eq(words.length(), 2)
      assert_eq(redirects.length(), 1)
      assert_eq(redirects[0].fd, 1)
      assert_eq(redirects[0].kind, Out)
    }
    _ => fail("Expected SimpleCommand with redirect")
  }
}

///|
test "parse redirect append" {
  let ast = parse("echo hello >> file.txt") catch {
    e => fail("Parse error: \{e}")
  }
  match ast {
    SimpleCommand(_, redirects) => assert_eq(redirects[0].kind, Append)
    _ => fail("Expected SimpleCommand with redirect")
  }
}

///|
test "parse if statement" {
  let ast = parse("if true; then echo yes; fi") catch {
    e => fail("Parse error: \{e}")
  }
  match ast {
    IfStmt(cond, then_body, elif_list, else_body) => {
      assert_true(cond is SimpleCommand(_))
      assert_true(then_body is SimpleCommand(_))
      assert_eq(elif_list.length(), 0)
      assert_true(else_body is None)
    }
    _ => fail("Expected IfStmt")
  }
}

///|
test "parse if else statement" {
  let ast = parse("if false; then echo no; else echo yes; fi") catch {
    e => fail("Parse error: \{e}")
  }
  match ast {
    IfStmt(_, _, _, else_body) => assert_true(else_body is Some(_))
    _ => fail("Expected IfStmt")
  }
}

///|
test "parse if elif else statement" {
  let ast = parse(
    "if false; then echo 1; elif true; then echo 2; else echo 3; fi",
  ) catch {
    e => fail("Parse error: \{e}")
  }
  match ast {
    IfStmt(_, _, elif_list, else_body) => {
      assert_eq(elif_list.length(), 1)
      assert_true(else_body is Some(_))
    }
    _ => fail("Expected IfStmt")
  }
}

///|
test "parse for loop" {
  let ast = parse("for i in a b c; do echo $i; done") catch {
    e => fail("Parse error: \{e}")
  }
  match ast {
    ForLoop(varname, items, _) => {
      assert_eq(varname, "i")
      assert_eq(items.length(), 3)
      assert_eq(items[0], Literal("a"))
      assert_eq(items[1], Literal("b"))
      assert_eq(items[2], Literal("c"))
    }
    _ => fail("Expected ForLoop")
  }
}

///|
test "parse while loop" {
  let ast = parse("while true; do echo x; done") catch {
    e => fail("Parse error: \{e}")
  }
  match ast {
    WhileLoop(_, _, is_until) => assert_false(is_until)
    _ => fail("Expected WhileLoop")
  }
}

///|
test "parse until loop" {
  let ast = parse("until false; do echo x; done") catch {
    e => fail("Parse error: \{e}")
  }
  match ast {
    WhileLoop(_, _, is_until) => assert_true(is_until)
    _ => fail("Expected WhileLoop (until)")
  }
}

///|
test "parse case statement" {
  let ast = parse("case x in a) echo a;; b) echo b;; esac") catch {
    e => fail("Parse error: \{e}")
  }
  match ast {
    CaseStmt(word, cases) => {
      assert_eq(word, Literal("x"))
      assert_eq(cases.length(), 2)
    }
    _ => fail("Expected CaseStmt")
  }
}

///|
test "parse test bracket" {
  let ast = parse("[ -f file.txt ]") catch { e => fail("Parse error: \{e}") }
  match ast {
    SimpleCommand(words, _) => {
      assert_eq(words[0], Literal("test"))
      assert_eq(words[1], Literal("-f"))
      assert_eq(words[2], Literal("file.txt"))
    }
    _ => fail("Expected SimpleCommand (test)")
  }
}

///|
test "parse assignment" {
  let ast = parse("NAME=value") catch { e => fail("Parse error: \{e}") }
  match ast {
    Assignment(name, value) => {
      assert_eq(name, "NAME")
      assert_eq(value, Literal("value"))
    }
    _ => fail("Expected Assignment")
  }
}

///|
test "parse variable in command" {
  let ast = parse("echo $NAME") catch { e => fail("Parse error: \{e}") }
  match ast {
    SimpleCommand(words, _) => {
      assert_eq(words.length(), 2)
      assert_eq(words[0], Literal("echo"))
      assert_eq(words[1], Word::Variable("NAME"))
    }
    _ => fail("Expected SimpleCommand")
  }
}

///|
test "parse complex command" {
  let ast = parse("cat file.txt | grep pattern && echo found || echo not found") catch {
    e => fail("Parse error: \{e}")
  }
  // Should be: OrList(AndList(Pipeline(...), ...), ...)
  match ast {
    OrList(AndList(Pipeline(_), _), _) => ()
    _ => fail("Expected OrList(AndList(Pipeline, ...), ...)")
  }
}

///|
test "parse empty input" {
  let ast = parse("") catch { e => fail("Parse error: \{e}") }
  assert_true(ast is Empty)
}

///|
test "parse with newlines" {
  let ast = parse("echo a\necho b") catch { e => fail("Parse error: \{e}") }
  match ast {
    Sequence(_, _) => ()
    _ => fail("Expected Sequence")
  }
}

///|
test "parse subshell" {
  let ast = parse("( echo hello )") catch { e => fail("Parse error: \{e}") }
  match ast {
    Subshell(body) => assert_true(body is SimpleCommand(_))
    _ => fail("Expected Subshell")
  }
}

///|
test "parse brace group" {
  let ast = parse("{ echo hello; }") catch { e => fail("Parse error: \{e}") }
  match ast {
    BraceGroup(body) => assert_true(body is SimpleCommand(_))
    _ => fail("Expected BraceGroup")
  }
}

///|
test "parse redirect with fd" {
  let ast = parse("cmd 2>&1") catch { e => fail("Parse error: \{e}") }
  match ast {
    SimpleCommand(words, redirects) => {
      assert_eq(words.length(), 1)
      assert_eq(redirects.length(), 1)
      assert_eq(redirects[0].fd, 2)
      assert_eq(redirects[0].kind, OutDup)
    }
    _ => fail("Expected SimpleCommand with redirect")
  }
}

///|
test "parse function definition" {
  let ast = parse("greet() { echo hello; }") catch {
    e => fail("Parse error: \{e}")
  }
  match ast {
    FuncDef(name, body) => {
      assert_eq(name, "greet")
      assert_true(body is BraceGroup(_))
    }
    _ => fail("Expected FuncDef, got \{ast}")
  }
}

///|
test "parse background" {
  let ast = parse("sleep 10 &") catch { e => fail("Parse error: \{e}") }
  match ast {
    Background(cmd) => assert_true(cmd is SimpleCommand(_))
    _ => fail("Expected Background, got \{ast}")
  }
}

///|
test "parse command substitution" {
  let ast = parse("echo $(pwd)") catch { e => fail("Parse error: \{e}") }
  match ast {
    SimpleCommand(words, _) => {
      assert_eq(words.length(), 2)
      assert_eq(words[0], Literal("echo"))
      assert_eq(words[1], CommandSub("pwd"))
    }
    _ => fail("Expected SimpleCommand, got \{ast}")
  }
}
