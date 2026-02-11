/// Minimatch - Glob pattern matching library
/// A minimal implementation of glob pattern matching

///|
/// Check if a string contains glob metacharacters
pub fn has_glob_chars(s : String) -> Bool {
  for c in s {
    if c == '*' || c == '?' || c == '[' {
      return true
    }
  }
  false
}

///|
/// Match a glob pattern against a string
/// Supports: * (any chars), ? (single char), [abc] (char class), [!abc] (negated)
pub fn match_(pattern : String, text : String) -> Bool {
  let pat = pattern.to_array()
  let txt = text.to_array()
  match_impl(pat, 0, txt, 0)
}

///|
fn match_impl(pat : Array[Char], pi : Int, txt : Array[Char], ti : Int) -> Bool {
  // Both exhausted - match
  if pi >= pat.length() && ti >= txt.length() {
    return true
  }

  // Pattern exhausted but text remains - no match
  if pi >= pat.length() {
    return false
  }

  let pc = pat[pi]

  match pc {
    '*' => {
      // Try matching * with 0 characters, then 1, 2, etc.
      for i = ti; i <= txt.length(); i = i + 1 {
        if match_impl(pat, pi + 1, txt, i) {
          return true
        }
      }
      false
    }
    '?' =>
      // Match exactly one character
      if ti < txt.length() {
        match_impl(pat, pi + 1, txt, ti + 1)
      } else {
        false
      }
    '[' => {
      // Character class
      if ti >= txt.length() {
        return false
      }
      let tc = txt[ti]
      let (matched, end_idx) = match_char_class(pat, pi + 1, tc)
      if matched {
        match_impl(pat, end_idx, txt, ti + 1)
      } else {
        false
      }
    }
    _ =>
      // Literal character
      if ti < txt.length() && txt[ti] == pc {
        match_impl(pat, pi + 1, txt, ti + 1)
      } else {
        false
      }
  }
}

///|
/// Match a character class [abc], [!abc], [a-z]
/// Returns (matched, index after ']')
fn match_char_class(pat : Array[Char], start : Int, c : Char) -> (Bool, Int) {
  let mut i = start
  let mut negate = false
  let mut matched = false

  // Check for negation
  if i < pat.length() && (pat[i] == '!' || pat[i] == '^') {
    negate = true
    i = i + 1
  }

  // Handle ] as first character (literal ])
  if i < pat.length() && pat[i] == ']' {
    if c == ']' {
      matched = true
    }
    i = i + 1
  }

  while i < pat.length() && pat[i] != ']' {
    // Check for range (a-z)
    if i + 2 < pat.length() && pat[i + 1] == '-' && pat[i + 2] != ']' {
      let start_c = pat[i]
      let end_c = pat[i + 2]
      if c >= start_c && c <= end_c {
        matched = true
      }
      i = i + 3
    } else {
      // Single character
      if pat[i] == c {
        matched = true
      }
      i = i + 1
    }
  }

  // Skip the closing ]
  if i < pat.length() && pat[i] == ']' {
    i = i + 1
  }

  let result = if negate { not(matched) } else { matched }
  (result, i)
}

///|
/// Filter an array of strings, keeping only those that match the pattern
pub fn filter(pattern : String, items : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for item in items {
    if match_(pattern, item) {
      result.push(item)
    }
  }
  result
}

///|
/// Check if any of the patterns match the text
pub fn match_any(patterns : Array[String], text : String) -> Bool {
  for pattern in patterns {
    if match_(pattern, text) {
      return true
    }
  }
  false
}

///|
/// Check if all patterns match the text
pub fn match_all(patterns : Array[String], text : String) -> Bool {
  for pattern in patterns {
    if not(match_(pattern, text)) {
      return false
    }
  }
  true
}
