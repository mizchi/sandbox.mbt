/// Shell parser - recursive descent parser for shell commands

///|
/// Parse error type
pub suberror ParseError {
  ParseError(String)
}

///|
pub impl Show for ParseError with output(self, logger) {
  match self {
    ParseError(msg) => logger.write_string("ParseError: \{msg}")
  }
}

///|
/// Parser for shell commands
pub struct Parser {
  tokens : Array[Token]
  mut pos : Int
}

///|
pub fn Parser::new(tokens : Array[Token]) -> Parser {
  { tokens, pos: 0 }
}

///|
fn Parser::peek(self : Parser) -> Token {
  if self.pos < self.tokens.length() {
    self.tokens[self.pos]
  } else {
    EOF
  }
}

///|
fn Parser::advance(self : Parser) -> Token {
  let tok = self.peek()
  self.pos += 1
  tok
}

///|
fn Parser::expect(self : Parser, expected : Token) -> Unit raise ParseError {
  let tok = self.advance()
  if tok != expected {
    raise ParseError("Expected \{expected}, got \{tok}")
  }
}

///|
fn Parser::skip_newlines(self : Parser) -> Unit {
  while true {
    match self.peek() {
      Newline => { let _ = self.advance() }
      _ => break
    }
  }
}

///|
fn Parser::is_command_end(self : Parser) -> Bool {
  match self.peek() {
    EOF | Semi | Newline | And | Or | Pipe | Then | Do | Done | Fi | Else |
    Elif | Esac | DoubleSemi | RightParen => true
    _ => false
  }
}

///|
/// Parse entire input
pub fn Parser::parse(self : Parser) -> Ast raise ParseError {
  self.skip_newlines()
  if self.peek() == EOF {
    return Empty
  }
  self.parse_list()
}

///|
/// Parse a list of commands (separated by ; or newlines)
fn Parser::parse_list(self : Parser) -> Ast raise ParseError {
  let mut result = self.parse_and_or()
  while true {
    match self.peek() {
      Semi => {
        let _ = self.advance()
        self.skip_newlines()
        if self.is_command_end() {
          break
        }
        let right = self.parse_and_or()
        result = Sequence(result, right)
      }
      Newline => {
        let _ = self.advance()
        self.skip_newlines()
        if self.is_command_end() || self.peek() == EOF {
          break
        }
        let right = self.parse_and_or()
        result = Sequence(result, right)
      }
      _ => break
    }
  }
  result
}

///|
/// Parse && and || operators
fn Parser::parse_and_or(self : Parser) -> Ast raise ParseError {
  let mut left = self.parse_pipeline()
  while true {
    match self.peek() {
      And => {
        let _ = self.advance()
        self.skip_newlines()
        let right = self.parse_pipeline()
        left = AndList(left, right)
      }
      Or => {
        let _ = self.advance()
        self.skip_newlines()
        let right = self.parse_pipeline()
        left = OrList(left, right)
      }
      _ => break
    }
  }
  left
}

///|
/// Parse pipeline (cmd | cmd | cmd)
fn Parser::parse_pipeline(self : Parser) -> Ast raise ParseError {
  let first = self.parse_command()
  let cmds : Array[Ast] = [first]
  while self.peek() == Pipe {
    let _ = self.advance()
    self.skip_newlines()
    cmds.push(self.parse_command())
  }
  if cmds.length() == 1 {
    cmds[0]
  } else {
    Pipeline(cmds)
  }
}

///|
/// Parse a single command (simple or compound)
fn Parser::parse_command(self : Parser) -> Ast raise ParseError {
  match self.peek() {
    If => self.parse_if()
    For => self.parse_for()
    While => self.parse_while()
    Until => self.parse_until()
    Case => self.parse_case()
    LeftBracket => self.parse_test_bracket()
    _ => self.parse_simple_command()
  }
}

///|
/// Parse simple command (command with args and redirects)
fn Parser::parse_simple_command(self : Parser) -> Ast raise ParseError {
  let words : Array[Word] = []
  let redirects : Array[Redirect] = []

  // Check for assignment
  match self.peek() {
    Assignment(name, value) => {
      let _ = self.advance()
      return Ast::Assignment(name, Literal(value))
    }
    _ => ()
  }

  while true {
    match self.peek() {
      Word(s) => {
        let _ = self.advance()
        words.push(Literal(s))
      }
      SingleQuotedWord(s) => {
        let _ = self.advance()
        words.push(Quoted([Literal(s)]))
      }
      DoubleQuotedWord(s) => {
        let _ = self.advance()
        words.push(Quoted([Literal(s)]))
      }
      Variable(s) => {
        let _ = self.advance()
        words.push(Word::Variable(s))
      }
      Token::ExitCode => {
        let _ = self.advance()
        words.push(Word::ExitCode)
      }
      ArgN(n) => {
        let _ = self.advance()
        words.push(Word::ArgN(n))
      }
      RedirectOut => {
        let _ = self.advance()
        let target = self.parse_word()
        redirects.push(Redirect::new(1, Out, target))
      }
      RedirectAppend => {
        let _ = self.advance()
        let target = self.parse_word()
        redirects.push(Redirect::new(1, Append, target))
      }
      RedirectIn => {
        let _ = self.advance()
        let target = self.parse_word()
        redirects.push(Redirect::new(0, In, target))
      }
      RedirectErr => {
        let _ = self.advance()
        let target = self.parse_word()
        redirects.push(Redirect::new(2, Out, target))
      }
      _ => break
    }
  }
  if words.length() == 0 && redirects.length() == 0 {
    Empty
  } else {
    SimpleCommand(words, redirects)
  }
}

///|
/// Parse a word (for redirect targets etc)
fn Parser::parse_word(self : Parser) -> Word raise ParseError {
  match self.peek() {
    Word(s) => {
      let _ = self.advance()
      Literal(s)
    }
    SingleQuotedWord(s) => {
      let _ = self.advance()
      Quoted([Literal(s)])
    }
    DoubleQuotedWord(s) => {
      let _ = self.advance()
      Quoted([Literal(s)])
    }
    Variable(s) => {
      let _ = self.advance()
      Word::Variable(s)
    }
    Token::ExitCode => {
      let _ = self.advance()
      Word::ExitCode
    }
    ArgN(n) => {
      let _ = self.advance()
      Word::ArgN(n)
    }
    tok => raise ParseError("Expected word, got \{tok}")
  }
}

///|
/// Parse if statement
fn Parser::parse_if(self : Parser) -> Ast raise ParseError {
  self.expect(If)
  self.skip_newlines()
  let cond = self.parse_list()
  self.skip_newlines()
  self.expect(Then)
  self.skip_newlines()
  let then_body = self.parse_list()

  // Parse elif clauses
  let elif_list : Array[(Ast, Ast)] = []
  while self.peek() == Elif {
    let _ = self.advance()
    self.skip_newlines()
    let elif_cond = self.parse_list()
    self.skip_newlines()
    self.expect(Then)
    self.skip_newlines()
    let elif_body = self.parse_list()
    elif_list.push((elif_cond, elif_body))
  }

  // Parse else clause
  let else_body : Ast? = if self.peek() == Else {
    let _ = self.advance()
    self.skip_newlines()
    Some(self.parse_list())
  } else {
    None
  }
  self.skip_newlines()
  self.expect(Fi)
  IfStmt(cond, then_body, elif_list, else_body)
}

///|
/// Parse for loop
fn Parser::parse_for(self : Parser) -> Ast raise ParseError {
  self.expect(For)
  let varname = match self.peek() {
    Word(s) => {
      let _ = self.advance()
      s
    }
    tok => raise ParseError("Expected variable name, got \{tok}")
  }

  // Parse "in items" (optional)
  let items : Array[Word] = []
  if self.peek() == In {
    let _ = self.advance()
    while true {
      match self.peek() {
        Word(s) => {
          let _ = self.advance()
          items.push(Literal(s))
        }
        SingleQuotedWord(s) => {
          let _ = self.advance()
          items.push(Quoted([Literal(s)]))
        }
        DoubleQuotedWord(s) => {
          let _ = self.advance()
          items.push(Quoted([Literal(s)]))
        }
        Variable(s) => {
          let _ = self.advance()
          items.push(Word::Variable(s))
        }
        _ => break
      }
    }
  }
  self.skip_newlines()
  match self.peek() {
    Semi => { let _ = self.advance() }
    _ => ()
  }
  self.skip_newlines()
  self.expect(Do)
  self.skip_newlines()
  let body = self.parse_list()
  self.skip_newlines()
  self.expect(Done)
  ForLoop(varname, items, body)
}

///|
/// Parse while loop
fn Parser::parse_while(self : Parser) -> Ast raise ParseError {
  self.expect(While)
  self.skip_newlines()
  let cond = self.parse_list()
  self.skip_newlines()
  match self.peek() {
    Semi => { let _ = self.advance() }
    _ => ()
  }
  self.skip_newlines()
  self.expect(Do)
  self.skip_newlines()
  let body = self.parse_list()
  self.skip_newlines()
  self.expect(Done)
  WhileLoop(cond, body, false)
}

///|
/// Parse until loop
fn Parser::parse_until(self : Parser) -> Ast raise ParseError {
  self.expect(Until)
  self.skip_newlines()
  let cond = self.parse_list()
  self.skip_newlines()
  match self.peek() {
    Semi => { let _ = self.advance() }
    _ => ()
  }
  self.skip_newlines()
  self.expect(Do)
  self.skip_newlines()
  let body = self.parse_list()
  self.skip_newlines()
  self.expect(Done)
  WhileLoop(cond, body, true)
}

///|
/// Parse case statement
fn Parser::parse_case(self : Parser) -> Ast raise ParseError {
  self.expect(Case)
  let word = self.parse_word()
  self.skip_newlines()
  self.expect(In)
  self.skip_newlines()

  let cases : Array[CaseItem] = []
  while self.peek() != Esac {
    // Parse pattern
    let patterns : Array[Word] = []
    patterns.push(self.parse_word())
    while self.peek() == Pipe {
      let _ = self.advance()
      patterns.push(self.parse_word())
    }
    self.expect(RightParen)
    self.skip_newlines()

    // Parse body
    let body = if self.peek() == DoubleSemi {
      Empty
    } else {
      self.parse_list()
    }
    if self.peek() == DoubleSemi {
      let _ = self.advance()
    }
    self.skip_newlines()
    cases.push(CaseItem::new(patterns, body))
  }
  self.expect(Esac)
  CaseStmt(word, cases)
}

///|
/// Parse test bracket command [ ... ]
fn Parser::parse_test_bracket(self : Parser) -> Ast raise ParseError {
  self.expect(LeftBracket)
  let words : Array[Word] = [Literal("test")]

  while self.peek() != RightBracket {
    match self.peek() {
      Word(s) => {
        let _ = self.advance()
        words.push(Literal(s))
      }
      SingleQuotedWord(s) => {
        let _ = self.advance()
        words.push(Quoted([Literal(s)]))
      }
      DoubleQuotedWord(s) => {
        let _ = self.advance()
        words.push(Quoted([Literal(s)]))
      }
      Variable(s) => {
        let _ = self.advance()
        words.push(Word::Variable(s))
      }
      Token::ExitCode => {
        let _ = self.advance()
        words.push(Word::ExitCode)
      }
      ArgN(n) => {
        let _ = self.advance()
        words.push(Word::ArgN(n))
      }
      EOF => raise ParseError("Unexpected EOF in test expression")
      tok => raise ParseError("Unexpected token in test: \{tok}")
    }
  }
  self.expect(RightBracket)
  SimpleCommand(words, [])
}

///|
/// Parse a string into AST
pub fn parse(input : String) -> Ast raise ParseError {
  let tokens = tokenize(input)
  let parser = Parser::new(tokens)
  parser.parse()
}
