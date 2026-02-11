/// Shell AST definitions

///|
/// Word with potential variable expansion
pub(all) enum Word {
  Literal(String)
  Variable(String)
  ExitCode // $?
  ArgN(Int) // $0, $1, ...
  ArgAll // $@ (all positional params as separate words)
  ArgAllString // $* (all positional params as single string)
  ArgCount // $#
  LastPid // $!
  ShellPid // $$
  Quoted(Array[Word]) // For double quoted strings with embedded variables
  CommandSub(String) // $(cmd) or `cmd`
}

///|
pub impl Show for Word with output(self, logger) {
  match self {
    Literal(s) => logger.write_string("Literal(\{s})")
    Variable(s) => logger.write_string("Variable($\{s})")
    ExitCode => logger.write_string("ExitCode($?)")
    ArgN(n) => logger.write_string("ArgN($\{n})")
    ArgAll => logger.write_string("ArgAll($@)")
    ArgAllString => logger.write_string("ArgAllString($*)")
    ArgCount => logger.write_string("ArgCount($#)")
    LastPid => logger.write_string("LastPid($!)")
    ShellPid => logger.write_string("ShellPid($$)")
    Quoted(words) => logger.write_string("Quoted(\{words})")
    CommandSub(cmd) => logger.write_string("CommandSub($(\{cmd}))")
  }
}

///|
pub impl Eq for Word with equal(self, other) {
  match (self, other) {
    (Literal(a), Literal(b)) => a == b
    (Variable(a), Variable(b)) => a == b
    (ExitCode, ExitCode) => true
    (ArgN(a), ArgN(b)) => a == b
    (ArgAll, ArgAll) => true
    (ArgAllString, ArgAllString) => true
    (ArgCount, ArgCount) => true
    (LastPid, LastPid) => true
    (ShellPid, ShellPid) => true
    (CommandSub(a), CommandSub(b)) => a == b
    (Quoted(a), Quoted(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i = 0; i < a.length(); i = i + 1 {
        if a[i] != b[i] {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// Redirect kind
pub(all) enum RedirectKind {
  Out // >
  Append // >>
  In // <
  OutDup // >&  (duplicate output fd)
  InDup // <&  (duplicate input fd)
  HereDoc // <<  (here document)
  HereDocStrip // <<- (here document with tab stripping)
}

///|
pub impl Show for RedirectKind with output(self, logger) {
  match self {
    Out => logger.write_string(">")
    Append => logger.write_string(">>")
    In => logger.write_string("<")
    OutDup => logger.write_string(">&")
    InDup => logger.write_string("<&")
    RedirectKind::HereDoc => logger.write_string("<<")
    RedirectKind::HereDocStrip => logger.write_string("<<-")
  }
}

///|
pub impl Eq for RedirectKind with equal(self, other) {
  match (self, other) {
    (Out, Out) => true
    (Append, Append) => true
    (In, In) => true
    (OutDup, OutDup) => true
    (InDup, InDup) => true
    (RedirectKind::HereDoc, RedirectKind::HereDoc) => true
    (RedirectKind::HereDocStrip, RedirectKind::HereDocStrip) => true
    _ => false
  }
}

///|
/// Redirect specification
pub struct Redirect {
  fd : Int // 1=stdout, 2=stderr
  kind : RedirectKind
  target : Word
}

///|
pub fn Redirect::new(fd : Int, kind : RedirectKind, target : Word) -> Redirect {
  { fd, kind, target }
}

///|
pub impl Show for Redirect with output(self, logger) {
  if self.fd != 1 {
    logger.write_string("\{self.fd}")
  }
  logger.write_string("\{self.kind}\{self.target}")
}

///|
/// Case item for case statement
pub struct CaseItem {
  patterns : Array[Word]
  body : Ast
}

///|
pub fn CaseItem::new(patterns : Array[Word], body : Ast) -> CaseItem {
  { patterns, body }
}

///|
/// Abstract Syntax Tree for shell commands
pub(all) enum Ast {
  // Simple command with redirects
  SimpleCommand(Array[Word], Array[Redirect])

  // Pipeline: cmd1 | cmd2 | cmd3
  Pipeline(Array[Ast])

  // Logical operators
  AndList(Ast, Ast) // cmd1 && cmd2
  OrList(Ast, Ast) // cmd1 || cmd2

  // Sequential execution
  Sequence(Ast, Ast) // cmd1 ; cmd2

  // If statement: cond, then_body, elif_list, else_body
  IfStmt(Ast, Ast, Array[(Ast, Ast)], Ast?)

  // For loop: variable_name, items, body
  ForLoop(String, Array[Word], Ast)

  // While/Until loop: cond, body, is_until
  WhileLoop(Ast, Ast, Bool)

  // Case statement: word, cases
  CaseStmt(Word, Array[CaseItem])

  // Variable assignment
  Assignment(String, Word)

  // Subshell: ( list )
  Subshell(Ast)

  // Brace group: { list; }
  BraceGroup(Ast)

  // Function definition: name() { body; }
  FuncDef(String, Ast)

  // Background execution: cmd &
  Background(Ast)

  // Empty command (no-op)
  Empty
}

///|
pub impl Show for Ast with output(self, logger) {
  match self {
    SimpleCommand(words, _) => {
      logger.write_string("SimpleCommand(")
      for i, w in words {
        if i > 0 {
          logger.write_string(" ")
        }
        w.output(logger)
      }
      logger.write_string(")")
    }
    Pipeline(cmds) => {
      logger.write_string("Pipeline(")
      for i, c in cmds {
        if i > 0 {
          logger.write_string(" | ")
        }
        c.output(logger)
      }
      logger.write_string(")")
    }
    AndList(l, r) => {
      logger.write_string("AndList(")
      l.output(logger)
      logger.write_string(" && ")
      r.output(logger)
      logger.write_string(")")
    }
    OrList(l, r) => {
      logger.write_string("OrList(")
      l.output(logger)
      logger.write_string(" || ")
      r.output(logger)
      logger.write_string(")")
    }
    Sequence(l, r) => {
      logger.write_string("Sequence(")
      l.output(logger)
      logger.write_string(" ; ")
      r.output(logger)
      logger.write_string(")")
    }
    IfStmt(_, _, _, _) => logger.write_string("IfStmt(...)")
    ForLoop(varname, _, _) => logger.write_string("ForLoop(\{varname}, ...)")
    WhileLoop(_, _, is_until) =>
      if is_until {
        logger.write_string("UntilLoop(...)")
      } else {
        logger.write_string("WhileLoop(...)")
      }
    CaseStmt(_, _) => logger.write_string("CaseStmt(...)")
    Assignment(name, value) =>
      logger.write_string("Assignment(\{name}=\{value})")
    Subshell(body) => {
      logger.write_string("Subshell(")
      body.output(logger)
      logger.write_string(")")
    }
    BraceGroup(body) => {
      logger.write_string("BraceGroup(")
      body.output(logger)
      logger.write_string(")")
    }
    FuncDef(name, body) => {
      logger.write_string("FuncDef(\{name}, ")
      body.output(logger)
      logger.write_string(")")
    }
    Background(cmd) => {
      logger.write_string("Background(")
      cmd.output(logger)
      logger.write_string(")")
    }
    Empty => logger.write_string("Empty")
  }
}

///|
/// Convert a token word to AST Word
pub fn token_to_word(token : Token) -> Word? {
  match token {
    Word(s) => Some(Literal(s))
    SingleQuotedWord(s) => Some(Quoted([Literal(s)]))
    DoubleQuotedWord(s) => Some(Quoted([Literal(s)]))
    Variable(s) => Some(Variable(s))
    ExitCode => Some(Word::ExitCode)
    ArgN(n) => Some(Word::ArgN(n))
    Token::ArgAll => Some(Word::ArgAll)
    Token::ArgAllString => Some(Word::ArgAllString)
    Token::ArgCount => Some(Word::ArgCount)
    Token::LastPid => Some(Word::LastPid)
    Token::ShellPid => Some(Word::ShellPid)
    Token::CommandSub(cmd) => Some(Word::CommandSub(cmd))
    _ => None
  }
}
