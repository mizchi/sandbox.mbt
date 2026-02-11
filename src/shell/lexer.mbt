/// Shell lexer - tokenizes shell command lines

///|
/// Token types for shell parsing
pub(all) enum Token {
  // Basic tokens
  Word(String) // Command, argument (unquoted)
  SingleQuotedWord(String) // 'literal' - no expansion
  DoubleQuotedWord(String) // "string" - variable expansion, no glob
  Assignment(String, String) // VAR=value

  // Variables
  Variable(String) // $VAR, ${VAR}
  ExitCode // $?
  ArgN(Int) // $0, $1...
  ArgAll // $@
  ArgAllString // $*
  ArgCount // $#
  LastPid // $!
  ShellPid // $$
  CommandSub(String) // $(cmd) or `cmd`

  // Operators
  Pipe // |
  And // &&
  Or // ||
  Semi // ;
  Amp // & (background)

  // Redirects
  RedirectOut // >
  RedirectAppend // >>
  RedirectIn // <
  RedirectErr // 2>
  RedirectOutAnd // >&
  RedirectInAnd // <&
  HereDoc(String, String) // <<DELIM content (delimiter, content)
  HereDocStrip(String, String) // <<-DELIM content (strip leading tabs)
  IoNumber(Int) // fd number before redirect (e.g., 2 in 2>&1)

  // Control keywords
  If
  Then
  Elif
  Else
  Fi
  For
  In
  Do
  Done
  While
  Until
  Case
  Esac

  // Brackets
  LeftBracket // [
  RightBracket // ]
  LeftParen // (
  RightParen // )
  LeftBrace // {
  RightBrace // }
  DoubleSemi // ;;

  // Special
  Newline
  EOF
}

///|
pub impl Show for Token with output(self, logger) {
  match self {
    Word(s) => logger.write_string("Word(\{s})")
    SingleQuotedWord(s) => logger.write_string("SingleQuotedWord('\{s}')")
    DoubleQuotedWord(s) => logger.write_string("DoubleQuotedWord(\"\{s}\")")
    Assignment(k, v) => logger.write_string("Assignment(\{k}=\{v})")
    Variable(s) => logger.write_string("Variable($\{s})")
    ExitCode => logger.write_string("ExitCode($?)")
    ArgN(n) => logger.write_string("ArgN($\{n})")
    ArgAll => logger.write_string("ArgAll($@)")
    ArgAllString => logger.write_string("ArgAllString($*)")
    ArgCount => logger.write_string("ArgCount($#)")
    LastPid => logger.write_string("LastPid($!)")
    ShellPid => logger.write_string("ShellPid($$)")
    CommandSub(cmd) => logger.write_string("CommandSub($(\{cmd}))")
    Pipe => logger.write_string("Pipe(|)")
    And => logger.write_string("And(&&)")
    Or => logger.write_string("Or(||)")
    Semi => logger.write_string("Semi(;)")
    Amp => logger.write_string("Amp(&)")
    RedirectOut => logger.write_string("RedirectOut(>)")
    RedirectAppend => logger.write_string("RedirectAppend(>>)")
    RedirectIn => logger.write_string("RedirectIn(<)")
    RedirectErr => logger.write_string("RedirectErr(2>)")
    RedirectOutAnd => logger.write_string("RedirectOutAnd(>&)")
    RedirectInAnd => logger.write_string("RedirectInAnd(<&)")
    HereDoc(delim, _) => logger.write_string("HereDoc(<<\{delim})")
    HereDocStrip(delim, _) => logger.write_string("HereDocStrip(<<-\{delim})")
    IoNumber(n) => logger.write_string("IoNumber(\{n})")
    If => logger.write_string("If")
    Then => logger.write_string("Then")
    Elif => logger.write_string("Elif")
    Else => logger.write_string("Else")
    Fi => logger.write_string("Fi")
    For => logger.write_string("For")
    In => logger.write_string("In")
    Do => logger.write_string("Do")
    Done => logger.write_string("Done")
    While => logger.write_string("While")
    Until => logger.write_string("Until")
    Case => logger.write_string("Case")
    Esac => logger.write_string("Esac")
    LeftBracket => logger.write_string("LeftBracket([)")
    RightBracket => logger.write_string("RightBracket(])")
    LeftParen => logger.write_string("LeftParen[(]")
    RightParen => logger.write_string("RightParen[)]")
    LeftBrace => logger.write_string("LeftBrace({)")
    RightBrace => logger.write_string("RightBrace(})")
    DoubleSemi => logger.write_string("DoubleSemi(;;)")
    Newline => logger.write_string("Newline")
    EOF => logger.write_string("EOF")
  }
}

///|
pub impl Eq for Token with equal(self, other) {
  match (self, other) {
    (Word(a), Word(b)) => a == b
    (SingleQuotedWord(a), SingleQuotedWord(b)) => a == b
    (DoubleQuotedWord(a), DoubleQuotedWord(b)) => a == b
    (Assignment(k1, v1), Assignment(k2, v2)) => k1 == k2 && v1 == v2
    (Variable(a), Variable(b)) => a == b
    (ExitCode, ExitCode) => true
    (ArgN(a), ArgN(b)) => a == b
    (ArgAll, ArgAll) => true
    (ArgAllString, ArgAllString) => true
    (ArgCount, ArgCount) => true
    (LastPid, LastPid) => true
    (ShellPid, ShellPid) => true
    (CommandSub(a), CommandSub(b)) => a == b
    (Pipe, Pipe) => true
    (And, And) => true
    (Or, Or) => true
    (Semi, Semi) => true
    (Amp, Amp) => true
    (RedirectOut, RedirectOut) => true
    (RedirectAppend, RedirectAppend) => true
    (RedirectIn, RedirectIn) => true
    (RedirectErr, RedirectErr) => true
    (RedirectOutAnd, RedirectOutAnd) => true
    (RedirectInAnd, RedirectInAnd) => true
    (HereDoc(d1, c1), HereDoc(d2, c2)) => d1 == d2 && c1 == c2
    (HereDocStrip(d1, c1), HereDocStrip(d2, c2)) => d1 == d2 && c1 == c2
    (IoNumber(a), IoNumber(b)) => a == b
    (If, If) => true
    (Then, Then) => true
    (Elif, Elif) => true
    (Else, Else) => true
    (Fi, Fi) => true
    (For, For) => true
    (In, In) => true
    (Do, Do) => true
    (Done, Done) => true
    (While, While) => true
    (Until, Until) => true
    (Case, Case) => true
    (Esac, Esac) => true
    (LeftBracket, LeftBracket) => true
    (RightBracket, RightBracket) => true
    (LeftParen, LeftParen) => true
    (RightParen, RightParen) => true
    (LeftBrace, LeftBrace) => true
    (RightBrace, RightBrace) => true
    (DoubleSemi, DoubleSemi) => true
    (Newline, Newline) => true
    (EOF, EOF) => true
    _ => false
  }
}

///|
/// Lexer for shell command lines
pub struct Lexer {
  input : Array[Char]
  mut pos : Int
  /// Whether we're at command position (start of line or after operators)
  mut at_command_pos : Bool
}

///|
pub fn Lexer::new(input : String) -> Lexer {
  { input: input.to_array(), pos: 0, at_command_pos: true }
}

///|
fn Lexer::peek(self : Lexer) -> Char? {
  if self.pos < self.input.length() {
    Some(self.input[self.pos])
  } else {
    None
  }
}

///|
fn Lexer::peek_at(self : Lexer, offset : Int) -> Char? {
  let idx = self.pos + offset
  if idx < self.input.length() {
    Some(self.input[idx])
  } else {
    None
  }
}

///|
fn Lexer::advance(self : Lexer) -> Char? {
  if self.pos < self.input.length() {
    let c = self.input[self.pos]
    self.pos += 1
    Some(c)
  } else {
    None
  }
}

///|
fn Lexer::skip_whitespace(self : Lexer) -> Unit {
  while true {
    match self.peek() {
      Some(' ') | Some('\t') => {
        let _ = self.advance()
      }
      _ => break
    }
  }
}

///|
fn Lexer::is_word_char(c : Char) -> Bool {
  match c {
    'a'..='z'
    | 'A'..='Z'
    | '0'..='9'
    | '_'
    | '-'
    | '.'
    | '/'
    | ':'
    | '~'
    | '*'
    | '?'
    | '@'
    | '+'
    | '%'
    | '=' => true
    _ => false
  }
}

///|
fn Lexer::is_identifier_char(c : Char) -> Bool {
  match c {
    'a'..='z' | 'A'..='Z' | '0'..='9' | '_' => true
    _ => false
  }
}

///|
fn Lexer::read_word(self : Lexer) -> String {
  let buf = StringBuilder::new()
  while true {
    match self.peek() {
      Some(c) =>
        if Lexer::is_word_char(c) {
          buf.write_char(c)
          let _ = self.advance()
        } else {
          break
        }
      None => break
    }
  }
  buf.to_string()
}

///|
fn Lexer::read_single_quoted(self : Lexer) -> String {
  // Skip opening quote
  let _ = self.advance()
  let buf = StringBuilder::new()
  while true {
    match self.advance() {
      Some('\'') => break
      Some(c) => buf.write_char(c)
      None => break
    }
  }
  buf.to_string()
}

///|
fn Lexer::read_double_quoted(self : Lexer) -> String {
  // Skip opening quote
  let _ = self.advance()
  let buf = StringBuilder::new()
  while true {
    match self.advance() {
      Some('"') => break
      Some('\\') =>
        // Handle escape sequences
        match self.advance() {
          Some(c) => buf.write_char(c)
          None => ()
        }
      Some(c) => buf.write_char(c)
      None => break
    }
  }
  buf.to_string()
}

///|
fn Lexer::read_variable(self : Lexer) -> Token {
  // Skip $
  let _ = self.advance()
  match self.peek() {
    Some('?') => {
      let _ = self.advance()
      ExitCode
    }
    Some('@') => {
      let _ = self.advance()
      ArgAll
    }
    Some('*') => {
      let _ = self.advance()
      ArgAllString
    }
    Some('#') => {
      let _ = self.advance()
      ArgCount
    }
    Some('!') => {
      let _ = self.advance()
      LastPid
    }
    Some('$') => {
      let _ = self.advance()
      ShellPid
    }
    Some('(') => {
      // $(cmd) - command substitution
      let _ = self.advance()
      self.read_command_substitution()
    }
    Some('{') => {
      // ${VAR}
      let _ = self.advance()
      let buf = StringBuilder::new()
      while true {
        match self.peek() {
          Some('}') => {
            let _ = self.advance()
            break
          }
          Some(c) if Lexer::is_identifier_char(c) => {
            buf.write_char(c)
            let _ = self.advance()
          }
          _ => break
        }
      }
      Variable(buf.to_string())
    }
    Some(c) if c >= '0' && c <= '9' => {
      let _ = self.advance()
      ArgN(c.to_int() - '0'.to_int())
    }
    Some(c) if Lexer::is_identifier_char(c) => {
      let buf = StringBuilder::new()
      while true {
        match self.peek() {
          Some(c) if Lexer::is_identifier_char(c) => {
            buf.write_char(c)
            let _ = self.advance()
          }
          _ => break
        }
      }
      Variable(buf.to_string())
    }
    _ => Word("$")
  }
}

///|
/// Read command substitution content $(...)
fn Lexer::read_command_substitution(self : Lexer) -> Token {
  let buf = StringBuilder::new()
  let mut depth = 1
  while depth > 0 {
    match self.peek() {
      Some('(') => {
        buf.write_char('(')
        depth += 1
        let _ = self.advance()
      }
      Some(')') => {
        depth -= 1
        if depth > 0 {
          buf.write_char(')')
        }
        let _ = self.advance()
      }
      Some(c) => {
        buf.write_char(c)
        let _ = self.advance()
      }
      None => break
    }
  }
  CommandSub(buf.to_string())
}

///|
/// Read backtick command substitution `...`
fn Lexer::read_backtick(self : Lexer) -> String {
  // Skip opening backtick
  let _ = self.advance()
  let buf = StringBuilder::new()
  while true {
    match self.peek() {
      Some('`') => {
        let _ = self.advance()
        break
      }
      Some('\\') => {
        // Handle escape in backticks
        let _ = self.advance()
        match self.peek() {
          Some(c) => {
            buf.write_char(c)
            let _ = self.advance()
          }
          None => break
        }
      }
      Some(c) => {
        buf.write_char(c)
        let _ = self.advance()
      }
      None => break
    }
  }
  buf.to_string()
}

///|
/// Read here document delimiter
fn Lexer::read_heredoc_delimiter(self : Lexer) -> String {
  let buf = StringBuilder::new()
  // Check for quoted delimiter
  match self.peek() {
    Some('\'') => {
      // Single-quoted delimiter - read until closing quote
      let _ = self.advance()
      while true {
        match self.peek() {
          Some('\'') => {
            let _ = self.advance()
            break
          }
          Some(c) => {
            buf.write_char(c)
            let _ = self.advance()
          }
          None => break
        }
      }
    }
    Some('"') => {
      // Double-quoted delimiter
      let _ = self.advance()
      while true {
        match self.peek() {
          Some('"') => {
            let _ = self.advance()
            break
          }
          Some(c) => {
            buf.write_char(c)
            let _ = self.advance()
          }
          None => break
        }
      }
    }
    _ =>
      // Unquoted delimiter - read word characters
      while true {
        match self.peek() {
          Some(c) if Lexer::is_word_char(c) => {
            buf.write_char(c)
            let _ = self.advance()
          }
          _ => break
        }
      }
  }
  buf.to_string()
}

///|
/// Read here document content until delimiter
fn Lexer::read_heredoc_content(
  self : Lexer,
  delim : String,
  strip_tabs : Bool,
) -> String {
  let buf = StringBuilder::new()
  // Skip to next line
  while true {
    match self.peek() {
      Some('\n') => {
        let _ = self.advance()
        break
      }
      Some(_) => {
        let _ = self.advance()
      }
      None => return buf.to_string()
    }
  }

  // Read content line by line
  while true {
    // Check if this line starts with delimiter
    let line_start = self.pos

    // Skip leading tabs if strip_tabs is true
    if strip_tabs {
      while self.peek() == Some('\t') {
        let _ = self.advance()
      }
    }

    // Check if the rest of the line is just the delimiter
    let mut match_pos = 0
    let delim_chars = delim.to_array()
    let mut is_match = true

    while match_pos < delim_chars.length() {
      match self.peek() {
        Some(c) if c == delim_chars[match_pos] => {
          match_pos += 1
          let _ = self.advance()
        }
        _ => {
          is_match = false
          break
        }
      }
    }

    // Check if we matched the full delimiter and are at end of line
    if is_match && match_pos == delim_chars.length() {
      match self.peek() {
        Some('\n') | None => {
          // Found delimiter, consume the newline and return
          let _ = self.advance()
          break
        }
        _ =>
          // Not a match, restore and continue
          self.pos = line_start
      }
    } else {
      // Not a match, restore position
      self.pos = line_start
    }

    // Read the line content
    while true {
      match self.peek() {
        Some('\n') => {
          buf.write_char('\n')
          let _ = self.advance()
          break
        }
        Some(c) => {
          buf.write_char(c)
          let _ = self.advance()
        }
        None => return buf.to_string()
      }
    }
  }

  buf.to_string()
}

///|
/// Convert word to keyword token if at command position
fn word_to_keyword(word : String, at_command_pos : Bool) -> Token {
  if at_command_pos {
    match word {
      "if" => If
      "then" => Then
      "elif" => Elif
      "else" => Else
      "fi" => Fi
      "for" => For
      "in" => In
      "do" => Do
      "done" => Done
      "while" => While
      "until" => Until
      "case" => Case
      "esac" => Esac
      _ => Word(word)
    }
  } else {
    // "in" is recognized after "for NAME"
    match word {
      "in" => In
      "then" => Then
      "do" => Do
      "done" => Done
      "fi" => Fi
      "elif" => Elif
      "else" => Else
      "esac" => Esac
      _ => Word(word)
    }
  }
}

///|
/// Get the next token
pub fn Lexer::next_token(self : Lexer) -> Token {
  self.skip_whitespace()
  match self.peek() {
    None => EOF
    Some('\n') => {
      let _ = self.advance()
      self.at_command_pos = true
      Newline
    }
    Some('#') => {
      // Skip comment until end of line
      while true {
        match self.peek() {
          Some('\n') | None => break
          _ => {
            let _ = self.advance()
          }
        }
      }
      self.next_token()
    }
    Some(';') => {
      let _ = self.advance()
      match self.peek() {
        Some(';') => {
          let _ = self.advance()
          self.at_command_pos = true
          DoubleSemi
        }
        _ => {
          self.at_command_pos = true
          Semi
        }
      }
    }
    Some('|') => {
      let _ = self.advance()
      match self.peek() {
        Some('|') => {
          let _ = self.advance()
          self.at_command_pos = true
          Or
        }
        _ => {
          self.at_command_pos = true
          Pipe
        }
      }
    }
    Some('&') => {
      let _ = self.advance()
      match self.peek() {
        Some('&') => {
          let _ = self.advance()
          self.at_command_pos = true
          And
        }
        _ => {
          // Background operator
          self.at_command_pos = true
          Amp
        }
      }
    }
    Some('`') => {
      // Backtick command substitution
      let cmd = self.read_backtick()
      self.at_command_pos = false
      CommandSub(cmd)
    }
    Some('>') => {
      let _ = self.advance()
      self.at_command_pos = false
      match self.peek() {
        Some('>') => {
          let _ = self.advance()
          RedirectAppend
        }
        Some('&') => {
          let _ = self.advance()
          RedirectOutAnd
        }
        _ => RedirectOut
      }
    }
    Some('<') => {
      let _ = self.advance()
      self.at_command_pos = false
      match self.peek() {
        Some('<') => {
          let _ = self.advance()
          // Here document
          let strip_tabs = match self.peek() {
            Some('-') => {
              let _ = self.advance()
              true
            }
            _ => false
          }
          self.skip_whitespace()
          // Read delimiter
          let delim = self.read_heredoc_delimiter()
          // Read content until we find the delimiter on its own line
          let content = self.read_heredoc_content(delim, strip_tabs)
          if strip_tabs {
            HereDocStrip(delim, content)
          } else {
            HereDoc(delim, content)
          }
        }
        Some('&') => {
          let _ = self.advance()
          RedirectInAnd
        }
        _ => RedirectIn
      }
    }
    Some(c) if c >= '0' && c <= '9' => {
      // Check if this is a fd number (digit followed by < or >)
      let next = self.peek_at(1)
      match next {
        Some('<') | Some('>') => {
          let fd = c.to_int() - '0'.to_int()
          let _ = self.advance() // consume digit
          self.at_command_pos = false
          IoNumber(fd)
        }
        _ => self.read_word_token()
      }
    }
    Some('[') => {
      let _ = self.advance()
      self.at_command_pos = false
      LeftBracket
    }
    Some(']') => {
      let _ = self.advance()
      self.at_command_pos = false
      RightBracket
    }
    Some('(') => {
      let _ = self.advance()
      self.at_command_pos = true
      LeftParen
    }
    Some(')') => {
      let _ = self.advance()
      self.at_command_pos = false
      RightParen
    }
    Some('{') => {
      let _ = self.advance()
      self.at_command_pos = true
      LeftBrace
    }
    Some('}') => {
      let _ = self.advance()
      self.at_command_pos = false
      RightBrace
    }
    Some('$') => {
      let token = self.read_variable()
      self.at_command_pos = false
      token
    }
    Some('\'') => {
      let s = self.read_single_quoted()
      self.at_command_pos = false
      SingleQuotedWord(s)
    }
    Some('"') => {
      let s = self.read_double_quoted()
      self.at_command_pos = false
      DoubleQuotedWord(s)
    }
    Some(_) => self.read_word_token()
  }
}

///|
fn Lexer::read_word_token(self : Lexer) -> Token {
  let word = self.read_word()
  if word.length() == 0 {
    // Unknown character, skip it
    let _ = self.advance()
    return self.next_token()
  }

  // Check for assignment (VAR=value)
  match word.find("=") {
    Some(idx) if idx > 0 && self.at_command_pos => {
      let name = substring_simple(word, 0, idx)
      let value = substring_simple(word, idx + 1, word.length())
      // Validate name is valid identifier
      let valid = name.iter().all(fn(c) { Lexer::is_identifier_char(c) })
      if valid {
        self.at_command_pos = true
        return Assignment(name, value)
      }
    }
    _ => ()
  }

  let token = word_to_keyword(word, self.at_command_pos)
  // After command, we're in argument position
  self.at_command_pos = false
  token
}

///|
/// Tokenize entire input
pub fn Lexer::tokenize(self : Lexer) -> Array[Token] {
  let tokens : Array[Token] = []
  while true {
    let tok = self.next_token()
    tokens.push(tok)
    if tok == EOF {
      break
    }
  }
  tokens
}

///|
/// Tokenize a string
pub fn tokenize(input : String) -> Array[Token] {
  Lexer::new(input).tokenize()
}

///|
fn substring_simple(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let buf = StringBuilder::new()
  for i = start; i < end && i < chars.length(); i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}
