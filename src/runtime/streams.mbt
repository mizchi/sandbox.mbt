/// Streams for process I/O

/// Pipe buffer for inter-process communication
pub struct Pipe {
  buffer : Array[Byte]
  mut closed : Bool
}

///|
pub fn Pipe::new() -> Pipe {
  { buffer: [], closed: false }
}

///|
pub fn Pipe::write(self : Pipe, data : Bytes) -> Int {
  if self.closed {
    return 0
  }
  for i in 0..<data.length() {
    self.buffer.push(data[i])
  }
  data.length()
}

///|
pub fn Pipe::write_string(self : Pipe, s : String) -> Int {
  self.write(@utf8.encode(s[:]))
}

///|
pub fn Pipe::read(self : Pipe, len : Int) -> Bytes {
  let actual_len = if len < self.buffer.length() { len } else { self.buffer.length() }
  if actual_len == 0 {
    return Bytes::new(0)
  }

  // Extract bytes from front of buffer
  let result = Bytes::makei(actual_len, fn(i) { self.buffer[i] })

  // Remove read bytes from buffer (shift remaining)
  let remaining : Array[Byte] = []
  for i in actual_len..<self.buffer.length() {
    remaining.push(self.buffer[i])
  }
  self.buffer.clear()
  for b in remaining {
    self.buffer.push(b)
  }

  result
}

///|
pub fn Pipe::read_all(self : Pipe) -> Bytes {
  self.read(self.buffer.length())
}

///|
pub fn Pipe::read_string(self : Pipe) -> String {
  @utf8.decode_lossy(self.read_all()[:])
}

///|
pub fn Pipe::close(self : Pipe) -> Unit {
  self.closed = true
}

///|
pub fn Pipe::is_closed(self : Pipe) -> Bool {
  self.closed
}

///|
pub fn Pipe::available(self : Pipe) -> Int {
  self.buffer.length()
}

/// Process I/O streams
pub struct ProcessIO {
  stdin : Pipe?
  stdout : Pipe?
  stderr : Pipe?
}

///|
pub fn ProcessIO::new() -> ProcessIO {
  { stdin: None, stdout: None, stderr: None }
}

///|
pub fn ProcessIO::with_pipes() -> ProcessIO {
  { stdin: Some(Pipe::new()), stdout: Some(Pipe::new()), stderr: Some(Pipe::new()) }
}

///|
pub fn ProcessIO::with_stdout() -> ProcessIO {
  { stdin: None, stdout: Some(Pipe::new()), stderr: None }
}

///|
pub fn ProcessIO::with_stderr() -> ProcessIO {
  { stdin: None, stdout: None, stderr: Some(Pipe::new()) }
}

///|
pub fn ProcessIO::with_stdout_stderr() -> ProcessIO {
  { stdin: None, stdout: Some(Pipe::new()), stderr: Some(Pipe::new()) }
}
