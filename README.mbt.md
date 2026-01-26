# sandbox.mbt

In-memory sandbox primitives for MoonBit.

## Features

- **MemFS** - In-memory filesystem with POSIX-like operations
- **POSIX Emulation** - File descriptors, pipes, processes
- **Shell** - Command execution and pipeline support
- **WASI Sandbox** - Configurable sandbox for WASI runtimes

## Installation

```json
{
  "deps": {
    "mizchi/sandbox": "0.1.0"
  }
}
```

## Usage

### MemFS

```moonbit
let fs = @sandbox.MemFS::new()
fs.write_file("/hello.txt", b"Hello, World!")
let content = fs.read_file("/hello.txt")
```

### Shell

```moonbit
let sandbox = @sandbox.Sandbox::new()
sandbox.exec("echo hello")
sandbox.exec("cat /etc/passwd | grep root")
```

## License

Apache-2.0
