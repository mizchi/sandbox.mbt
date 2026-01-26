# WASI Preview 3 Implementation Plan for sandbox.mbt

## Overview

This document outlines the plan for implementing WASI Preview 3 (WASI 0.3) support in sandbox.mbt, enabling MoonBit wasm modules to run with native async I/O capabilities.

## Background

### WASI P3 Status (as of 2025)

- **Specification**: Draft, expected completion ~February 2026
- **Core Features**: Native async in Component Model, `stream<T>`, `future<T>`
- **Runtime Support**: wasmtime 37+ (previews available)

### Current sandbox.mbt Assets

| Component | Status | WASI P3 Mapping |
|-----------|--------|-----------------|
| `sandbox_async/future.mbt` | Implemented | `future<T>` |
| `sandbox_async/byte_stream.mbt` | Implemented | `stream<u8>` |
| `sandbox_async/channel.mbt` | Implemented | Internal messaging |
| `sandbox_async/waitable.mbt` | Implemented | `pollable` base |
| `sandbox/memfs.mbt` | Implemented | `wasi:filesystem` |
| `sandbox/wasi_sandbox.mbt` | Implemented | Capability system |

## Target: x-async wasm-gc Support

The immediate goal is enabling x-async's wasm-gc target to run in sandbox.mbt with proper async support.

### Required WASI P2 Interfaces (Minimal)

```
wasi:io/poll@0.2.9
├── [resource-drop]pollable
├── [method]pollable.ready
├── [method]pollable.block
└── poll

wasi:clocks/monotonic-clock@0.2.9
├── subscribe-duration
└── now

wasi:io/streams@0.2.9 (optional, for full I/O)
├── input-stream
└── output-stream
```

## Architecture

### Layer 1: Core Primitives (sandbox_async)

Already implemented:
- `Future[T]` - single-value async channel
- `ByteStream` - unbuffered byte stream
- `Waitable` - pollable abstraction
- `Task` - async task management

### Layer 2: WASI Interface Binding (NEW: src/wasi)

```
src/wasi/
├── io/
│   ├── poll.mbt         # Pollable resource management
│   └── streams.mbt      # Input/Output streams
├── clocks/
│   └── monotonic.mbt    # Timer subscriptions
├── filesystem/
│   └── types.mbt        # File descriptors, paths
└── exports.mbt          # Host function exports
```

### Layer 3: Runtime Integration (NEW: src/runtime)

```
src/runtime/
├── wasm_host.mbt        # WASI import provider
├── event_loop.mbt       # Async event loop
└── scheduler.mbt        # Coroutine scheduler
```

## Implementation Phases

### Phase 1: Pollable & Clocks (Priority: HIGH)

**Goal**: Enable `@async.sleep()` in wasm-gc

```moonbit
// src/wasi/io/poll.mbt

pub struct Pollable {
  id : Int
  waitable : Waitable
}

pub fn Pollable::ready(self : Pollable) -> Bool {
  self.waitable.is_ready()
}

pub fn Pollable::block(self : Pollable) -> Unit {
  // Synchronous block until ready
  while not(self.ready()) {
    // Yield to scheduler or busy-wait
  }
}

pub fn poll(pollables : Array[Pollable]) -> FixedArray[UInt] {
  // Block until at least one is ready
  // Return indices of ready pollables
}
```

```moonbit
// src/wasi/clocks/monotonic.mbt

pub fn subscribe_duration(ns : UInt64) -> Pollable {
  let deadline = monotonic_now() + ns
  Pollable::new_timer(deadline)
}

pub fn monotonic_now() -> UInt64 {
  // Current monotonic time in nanoseconds
}
```

**Deliverables**:
- [ ] `Pollable` type with ready/block methods
- [ ] `poll()` for multiple pollables
- [ ] `subscribe_duration()` for timers
- [ ] Integration with `sandbox_async/waitable.mbt`

### Phase 2: Streams (Priority: MEDIUM)

**Goal**: Enable `@async.read()`, `@async.write()` with streams

```moonbit
// src/wasi/io/streams.mbt

pub struct InputStream {
  inner : ReadEnd  // From sandbox_async/byte_stream
}

pub struct OutputStream {
  inner : WriteEnd
}

pub fn InputStream::subscribe(self : InputStream) -> Pollable {
  // Returns pollable that's ready when data available
}

pub fn InputStream::read(self : InputStream, len : UInt64) -> Bytes {
  // Non-blocking read
}

pub fn OutputStream::subscribe(self : OutputStream) -> Pollable {
  // Returns pollable that's ready when writable
}

pub fn OutputStream::write(self : OutputStream, data : Bytes) -> UInt64 {
  // Non-blocking write, returns bytes written
}
```

**Deliverables**:
- [ ] `InputStream` / `OutputStream` types
- [ ] Stream subscription (pollable)
- [ ] Non-blocking read/write
- [ ] Bridge to existing `ByteStream`

### Phase 3: Filesystem (Priority: MEDIUM)

**Goal**: Enable `@fs.read_file()`, `@fs.write_file()`

```moonbit
// src/wasi/filesystem/types.mbt

pub struct Descriptor {
  fd : Fd
  sandbox : WasiSandbox
}

pub fn Descriptor::read_via_stream(self : Descriptor) -> InputStream {
  // Get input stream for file
}

pub fn Descriptor::write_via_stream(self : Descriptor) -> OutputStream {
  // Get output stream for file
}
```

**Deliverables**:
- [ ] `Descriptor` type wrapping fd
- [ ] Stream-based file I/O
- [ ] Directory operations
- [ ] Integration with `MemFS`

### Phase 4: Event Loop Integration (Priority: HIGH)

**Goal**: Proper async execution with multiple concurrent tasks

```moonbit
// src/runtime/event_loop.mbt

pub struct EventLoop {
  scheduler : Scheduler
  pending_pollables : Map[Int, Coroutine]
}

pub fn EventLoop::run(self : EventLoop, main : async () -> Unit) -> Unit {
  // 1. Spawn main as coroutine
  // 2. Loop:
  //    a. Run ready coroutines
  //    b. Check pollables for ready state
  //    c. Wake ready coroutines
  //    d. If all blocked, poll() for I/O
}

pub fn EventLoop::register_pollable(
  self : EventLoop,
  pollable : Pollable,
  coro : Coroutine
) -> Unit {
  self.pending_pollables.set(pollable.id, coro)
}
```

**Deliverables**:
- [ ] Event loop with pollable tracking
- [ ] Proper concurrent task execution
- [ ] Integration with `sandbox_async/task.mbt`

### Phase 5: WASM Host Binding (Priority: HIGH)

**Goal**: Provide WASI imports to wasm modules

```moonbit
// src/runtime/wasm_host.mbt

pub struct WasiHost {
  event_loop : EventLoop
  filesystem : WasiSandbox
  clocks : MonotonicClock
}

/// Generate import object for wasm instantiation
pub fn WasiHost::get_imports(self : WasiHost) -> Map[String, Map[String, HostFunc]] {
  {
    "wasi:io/poll@0.2.9": {
      "[resource-drop]pollable": fn(id) { self.drop_pollable(id) },
      "[method]pollable.ready": fn(id) { self.pollable_ready(id) },
      "[method]pollable.block": fn(id) { self.pollable_block(id) },
      "poll": fn(list, ret) { self.poll(list, ret) },
    },
    "wasi:clocks/monotonic-clock@0.2.9": {
      "subscribe-duration": fn(ns) { self.subscribe_duration(ns) },
      "now": fn() { self.monotonic_now() },
    },
    "spectest": {
      "print_char": fn(c) { print_char(c) },
    },
  }
}
```

**Deliverables**:
- [ ] Host function registration system
- [ ] Memory access helpers (for wasm linear memory)
- [ ] Resource ID management
- [ ] Integration with wasm interpreter (if available)

## Testing Strategy

### Unit Tests

```moonbit
test "pollable_timer" {
  let p = subscribe_duration(10_000_000UL)  // 10ms
  assert_false(p.ready())
  p.block()
  assert_true(p.ready())
}

test "stream_roundtrip" {
  let (read, write) = new_byte_stream()
  let input = InputStream::new(read)
  let output = OutputStream::new(write)

  spawn(async fn() { output.write(b"hello") })
  let data = input.read(5)
  assert_eq(data, b"hello")
}
```

### Integration Tests

1. Run x-async's `sleep` example in sandbox
2. Run concurrent task demo
3. Run file I/O operations

## Dependencies

### Required

- `sandbox_async` (already in sandbox.mbt)
- `coroutine` runtime (already in sandbox.mbt)

### Optional

- wasm interpreter for full WASI host mode
- External time source for real timers (vs simulated)

## Timeline Estimate

| Phase | Scope | Status |
|-------|-------|--------|
| Phase 1 | Pollable & Clocks | Not started |
| Phase 2 | Streams | Not started |
| Phase 3 | Filesystem | Not started |
| Phase 4 | Event Loop | Not started |
| Phase 5 | WASM Host | Not started |

## Open Questions

1. **Component Model**: Do we need Component Model support, or is core wasm sufficient?
   - Current plan: Core wasm with WASI P2 imports (simpler)

2. **Real vs Simulated Time**: Should timers use real wall-clock time or simulated time?
   - Simulated is easier for testing, real is needed for actual async I/O

3. **WASM Interpreter**: Do we need a full wasm interpreter in sandbox.mbt, or is this for host-side use only?
   - Current plan: Focus on host-side WASI provider first

4. **Memory Model**: How to handle wasm linear memory access from MoonBit?
   - Need FFI or memory abstraction layer

## References

- [WASI 0.3 Roadmap](https://wasi.dev/roadmap)
- [Component Model Async](https://github.com/WebAssembly/component-model/blob/main/design/mvp/Async.md)
- [x-async WASI implementation](https://github.com/mizchi/x-async/tree/main/src/wasi)
- [wasmtime WASI P3 prototyping](https://github.com/bytecodealliance/wasip3-prototyping)
