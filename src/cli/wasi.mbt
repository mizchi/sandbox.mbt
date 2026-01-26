/// WASI Preview 1 FFI bindings for interactive shell

///|
/// WASI fd_write - write to a file descriptor
fn wasi_fd_write(
  fd : Int,
  iovs_ptr : Int,
  iovs_len : Int,
  nwritten_ptr : Int
) -> Int = "wasi_snapshot_preview1" "fd_write"

///|
/// WASI fd_read - read from a file descriptor
fn wasi_fd_read(
  fd : Int,
  iovs_ptr : Int,
  iovs_len : Int,
  nread_ptr : Int
) -> Int = "wasi_snapshot_preview1" "fd_read"

// Memory helpers
///|
extern "wasm" fn wasm_memory_ptr(arr : FixedArray[Byte]) -> Int =
  #|(func (param i32) (result i32) local.get 0 i32.const 8 i32.add)

///|
extern "wasm" fn wasm_i32_store(ptr : Int, val : Int) -> Unit =
  #|(func (param i32) (param i32) local.get 0 local.get 1 i32.store)

///|
extern "wasm" fn wasm_i32_load(ptr : Int) -> Int =
  #|(func (param i32) (result i32) local.get 0 i32.load)

// Standard file descriptors
let stdin_fd : Int = 0
let stdout_fd : Int = 1

///|
/// Write string to stdout
pub fn write_stdout(s : String) -> Unit {
  let bytes = s.to_array().map(fn(c) { c.to_int().to_byte() })
  let buf = FixedArray::from_iter(bytes.iter())
  let iov = FixedArray::make(8, b'\x00')
  let iov_ptr = wasm_memory_ptr(iov)
  let buf_ptr = wasm_memory_ptr(buf)
  wasm_i32_store(iov_ptr, buf_ptr)
  wasm_i32_store(iov_ptr + 4, buf.length())
  let nwritten_buf = FixedArray::make(4, b'\x00')
  let nwritten_ptr = wasm_memory_ptr(nwritten_buf)
  ignore(wasi_fd_write(stdout_fd, iov_ptr, 1, nwritten_ptr))
}

///|
/// Read a line from stdin
pub fn read_line() -> String? {
  let result = StringBuilder::new()
  let buf = FixedArray::make(1, b'\x00')
  let iov = FixedArray::make(8, b'\x00')
  let iov_ptr = wasm_memory_ptr(iov)
  let buf_ptr = wasm_memory_ptr(buf)
  wasm_i32_store(iov_ptr, buf_ptr)
  wasm_i32_store(iov_ptr + 4, 1)
  let nread_buf = FixedArray::make(4, b'\x00')
  let nread_ptr = wasm_memory_ptr(nread_buf)
  while true {
    let err = wasi_fd_read(stdin_fd, iov_ptr, 1, nread_ptr)
    if err != 0 {
      return None
    }
    let nread = wasm_i32_load(nread_ptr)
    if nread == 0 {
      // EOF
      if result.to_string().length() > 0 {
        return Some(result.to_string())
      } else {
        return None
      }
    }
    let c = buf[0].to_int()
    if c == '\n'.to_int() {
      return Some(result.to_string())
    }
    result.write_char(c.unsafe_to_char())
  }
  None
}
