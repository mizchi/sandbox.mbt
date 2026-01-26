# sandbox.mbt

In-memory sandbox primitives for MoonBit - virtual filesystem, POSIX emulation, and bash-compatible shell.

## Features

- **Fs** - In-memory filesystem with full POSIX-like operations
- **FileSystem Trait** - Pluggable backend support (Fs, S3, SQLite, etc.)
- **POSIX Emulation** - File descriptors, environment variables, process management
- **Bash-compatible Shell** - Full shell interpreter with:
  - Operators: `&&`, `||`, `|`, `;`
  - Control structures: `if/elif/else/fi`, `for/in/do/done`, `while/do/done`, `case/esac`
  - Variables: `$VAR`, `${VAR}`, `$?`, `$0`-`$9`
  - Test command: `test`, `[` with `-f`, `-d`, `-z`, `-n`, `=`, `-eq`, `-lt`, `-gt`
  - Redirects: `>`, `>>`, `<`
- **Interactive CLI** - Native interactive shell with pluggable backends

## Installation

```bash
moon add mizchi/sandbox
```

## Usage

### Shell

```moonbit
let ctx = @posix.PosixContext::default()
let shell = @shell.Shell::new(ctx)

// Simple commands
let result = shell.exec_line("echo Hello, World!")
println(result.stdout) // "Hello, World!\n"

// Variables and control flow
shell.exec_line("NAME=MoonBit")
shell.exec_line("echo Hello, $NAME!")

// Conditionals
shell.exec_line("if test -f /file.txt; then echo exists; else echo not found; fi")

// Loops
shell.exec_line("for i in a b c; do echo $i; done")

// Logical operators
shell.exec_line("test -d /tmp && echo 'tmp exists'")
shell.exec_line("false || echo 'fallback'")
```

### Fs (In-memory Filesystem)

```moonbit
let fs = @fs.Fs::new()

// File operations
fs.write_string("/hello.txt", "Hello, World!")
let content = fs.read_string("/hello.txt")

// Directory operations
fs.mkdir("/mydir")
fs.mkdir_p("/deep/nested/path")
let entries = fs.readdir("/")

// Symlinks
fs.symlink("/link", "/hello.txt")
```

### Custom Filesystem Backend

```moonbit
// Use Fs (default)
let fs = @fs.Fs::default()
let ctx = @posix.PosixContext::new(fs)

// Use S3 backend (stub - implement for real S3)
let fs = @fs.S3Backend::new("my-bucket")
let ctx = @posix.PosixContext::new(fs)

// Use SQLite backend (stub - implement for real SQLite)
let fs = @fs.SqliteBackend::new("/path/to/db.sqlite")
let ctx = @posix.PosixContext::new(fs)
```

### Interactive CLI

```bash
# Run interactive shell (native target)
moon run src/cli --target native

# Output:
# MoonBit Shell
# Backend: memory
# Type 'exit' to quit
#
# $ echo Hello
# Hello
# $ for i in 1 2 3; do echo $i; done
# 1
# 2
# 3
# $ exit
```

## Architecture

```
src/
├── fs/           # Filesystem layer
│   ├── backend.mbt       # FileSystem trait
│   ├── memfs.mbt         # In-memory implementation
│   └── stub_backends.mbt # S3/SQLite stubs
├── posix/        # POSIX emulation layer
│   ├── posix.mbt         # PosixContext (fd, env, process)
│   └── types.mbt         # POSIX types (Fd, Errno, etc.)
├── shell/        # Shell interpreter
│   ├── lexer.mbt         # Tokenizer
│   ├── ast.mbt           # Abstract syntax tree
│   ├── parser.mbt        # Recursive descent parser
│   ├── executor.mbt      # AST execution engine
│   ├── variables.mbt     # Variable expansion
│   └── shell.mbt         # Shell interface
└── cli/          # Command-line interface
    ├── main_native.mbt   # Interactive shell (native)
    └── main_demo.mbt     # Demo mode (wasm-gc)
```

## License

Apache-2.0
