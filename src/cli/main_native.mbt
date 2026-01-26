/// Interactive Shell CLI (native target)
/// Uses native stdin/stdout for interactive input

// Native FFI for stdin/stdout
///|
extern "C" fn native_getchar() -> Int = "getchar"

///|
extern "C" fn native_putchar(c : Int) -> Int = "putchar"

///|
extern "C" fn native_fflush(stream : Int) -> Int = "fflush"

///|
fn write_string(s : String) -> Unit {
  for c in s {
    ignore(native_putchar(c.to_int()))
  }
  ignore(native_fflush(0)) // flush stdout
}

///|
fn read_line_native() -> String? {
  let result = StringBuilder::new()
  while true {
    let c = native_getchar()
    if c == -1 {
      // EOF
      if result.to_string().length() > 0 {
        return Some(result.to_string())
      } else {
        return None
      }
    }
    if c == '\n'.to_int() {
      return Some(result.to_string())
    }
    result.write_char(c.unsafe_to_char())
  }
  None
}

///|
/// Backend type for filesystem
pub(all) enum BackendType {
  Memory
  S3(String) // bucket name
  Sqlite(String) // db path
}

///|
/// Create memory filesystem backend
fn create_memory_backend() -> &@fs.FileSystem {
  @fs.Fs::default()
}

///|
/// Create S3 filesystem backend
fn create_s3_backend(bucket : String) -> &@fs.FileSystem {
  @fs.S3Backend::new(bucket)
}

///|
/// Create SQLite filesystem backend
fn create_sqlite_backend(path : String) -> &@fs.FileSystem {
  @fs.SqliteBackend::new(path)
}

///|
fn main {
  // Default to memory backend
  // In a real CLI, parse command-line arguments here
  let backend_type : BackendType = Memory
  let (fs, backend_name) : (&@fs.FileSystem, String) = match backend_type {
    Memory => (create_memory_backend(), "memory")
    S3(bucket) => (create_s3_backend(bucket), "s3://" + bucket)
    Sqlite(path) => (create_sqlite_backend(path), "sqlite://" + path)
  }
  let ctx = @posix.PosixContext::new(fs)
  let shell = @shell.Shell::new(ctx)

  write_string("MoonBit Shell\n")
  write_string("Backend: " + backend_name + "\n")
  write_string("Type 'exit' to quit\n\n")

  let mut running = true
  while running {
    write_string("$ ")
    match read_line_native() {
      None => {
        write_string("\n")
        running = false
      }
      Some(line) => {
        let trimmed = line.trim().to_string()
        if trimmed == "exit" || trimmed == "exit 0" {
          running = false
        } else if trimmed.length() > 0 {
          let result = shell.exec_line(trimmed)
          if not(result.stdout.is_empty()) {
            write_string(result.stdout)
          }
          if not(result.stderr.is_empty()) {
            write_string(result.stderr)
          }
        }
      }
    }
  }
}
