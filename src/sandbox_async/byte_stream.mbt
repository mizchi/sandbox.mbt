/// ByteStream - WASI 0.3 stream<u8> compatible unbuffered stream
///
/// Design notes:
/// - Unbuffered: data is transferred directly between reader and writer
/// - Single reader, single writer
/// - Async read blocks until data is available or stream is closed
/// - Async write blocks until reader consumes the data

/// Stream state
pub(all) enum StreamState {
  Empty
  HasData(Bytes)
  Closed
}

/// Internal shared state between read and write ends (exposed for Waitable impl)
pub struct StreamInner {
  mut state : StreamState
  mut reader_waiting : @coroutine.Coroutine?
  mut writer_waiting : @coroutine.Coroutine?
}

/// Wake waiting reader if present
fn StreamInner::wake_reader(self : StreamInner) -> Unit {
  match self.reader_waiting {
    Some(coro) => {
      self.reader_waiting = None
      coro.wake()
    }
    None => ()
  }
}

/// Wake waiting writer if present
fn StreamInner::wake_writer(self : StreamInner) -> Unit {
  match self.writer_waiting {
    Some(coro) => {
      self.writer_waiting = None
      coro.wake()
    }
    None => ()
  }
}

/// Readable end of a ByteStream
pub struct ReadEnd {
  inner : StreamInner
}

/// Writable end of a ByteStream
pub struct WriteEnd {
  inner : StreamInner
}

/// Create a new (readable, writable) stream pair
pub fn new_byte_stream() -> (ReadEnd, WriteEnd) {
  let inner : StreamInner = {
    state: Empty,
    reader_waiting: None,
    writer_waiting: None,
  }
  ({ inner, }, { inner, })
}

/// Read from the stream. Blocks until data is available or stream is closed.
/// Returns empty Bytes if stream is closed.
pub async fn ReadEnd::read(self : ReadEnd) -> Bytes {
  while true {
    match self.inner.state {
      HasData(data) => {
        self.inner.state = Empty
        self.inner.wake_writer()
        return data
      }
      Closed => return Bytes::new(0)
      Empty => {
        // Wait for data
        self.inner.reader_waiting = Some(@coroutine.current_coroutine())
        @coroutine.suspend()
      }
    }
  }
  // Unreachable, but needed for type checker
  Bytes::new(0)
}

/// Check if data is available without blocking
pub fn ReadEnd::poll(self : ReadEnd) -> Bytes? {
  match self.inner.state {
    HasData(data) => {
      self.inner.state = Empty
      self.inner.wake_writer()
      Some(data)
    }
    _ => None
  }
}

/// Check if stream is closed
pub fn ReadEnd::is_closed(self : ReadEnd) -> Bool {
  self.inner.state is Closed
}

/// Write to the stream. Blocks until reader consumes the data.
/// Returns false if stream is closed.
pub async fn WriteEnd::write(self : WriteEnd, data : Bytes) -> Bool {
  // Wait until stream is empty, then put data
  while true {
    match self.inner.state {
      Closed => return false
      HasData(_) => {
        // Wait for reader to consume
        self.inner.writer_waiting = Some(@coroutine.current_coroutine())
        @coroutine.suspend()
      }
      Empty => {
        // Put data and wake reader
        self.inner.state = HasData(data)
        self.inner.wake_reader()

        // Wait for reader to consume (unbuffered semantics)
        self.inner.writer_waiting = Some(@coroutine.current_coroutine())
        @coroutine.suspend()

        // Check result after waking
        match self.inner.state {
          Empty => return true  // Reader consumed
          Closed => return false  // Stream closed
          HasData(_) => continue  // Spurious wakeup, retry
        }
      }
    }
  }
  // Unreachable
  false
}

/// Write string to the stream
pub async fn WriteEnd::write_string(self : WriteEnd, s : String) -> Bool {
  self.write(Bytes::from_iter(s.iter().map(fn(c) { c.to_int().to_byte() })))
}

/// Close the writable end
pub fn WriteEnd::close(self : WriteEnd) -> Unit {
  self.inner.state = Closed
  self.inner.wake_reader()
}

/// Check if stream is closed
pub fn WriteEnd::is_closed(self : WriteEnd) -> Bool {
  self.inner.state is Closed
}
