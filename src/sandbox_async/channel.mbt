/// Channel - Buffered multi-value channel
///
/// Unlike ByteStream (unbuffered) and Future (single-value),
/// Channel supports buffered multi-value communication.

/// Channel state
pub(all) enum ChannelState {
  Open
  Closed
}

/// Internal channel state
pub struct ChannelInner[T] {
  mut state : ChannelState
  buffer : Array[T]
  capacity : Int  // 0 = unbounded
  receivers : Array[@coroutine.Coroutine]
  senders : Array[@coroutine.Coroutine]
}

/// Sender end of channel
pub struct Sender[T] {
  inner : ChannelInner[T]
}

/// Receiver end of channel
pub struct Receiver[T] {
  inner : ChannelInner[T]
}

/// Create a new unbounded channel
pub fn[T] new_channel() -> (Sender[T], Receiver[T]) {
  new_channel_with_capacity(0)
}

/// Create a new bounded channel with specified capacity
pub fn[T] new_channel_with_capacity(capacity : Int) -> (Sender[T], Receiver[T]) {
  let inner : ChannelInner[T] = {
    state: Open,
    buffer: [],
    capacity,
    receivers: [],
    senders: [],
  }
  ({ inner, }, { inner, })
}

/// Send a value to the channel
/// Blocks if buffer is full (for bounded channels)
pub async fn[T] Sender::send(self : Sender[T], value : T) -> Bool {
  while true {
    match self.inner.state {
      Closed => return false
      Open => {
        // Check if buffer has room
        if self.inner.capacity == 0 || self.inner.buffer.length() < self.inner.capacity {
          self.inner.buffer.push(value)
          // Wake a receiver if waiting
          if self.inner.receivers.length() > 0 {
            match self.inner.receivers.pop() {
              Some(coro) => coro.wake()
              None => ()
            }
          }
          return true
        } else {
          // Buffer full, wait
          self.inner.senders.push(@coroutine.current_coroutine())
          @coroutine.suspend()
        }
      }
    }
  }
  false
}

/// Try to send without blocking
pub fn[T] Sender::try_send(self : Sender[T], value : T) -> Bool {
  match self.inner.state {
    Closed => false
    Open => {
      if self.inner.capacity == 0 || self.inner.buffer.length() < self.inner.capacity {
        self.inner.buffer.push(value)
        if self.inner.receivers.length() > 0 {
          match self.inner.receivers.pop() {
            Some(coro) => coro.wake()
            None => ()
          }
        }
        true
      } else {
        false
      }
    }
  }
}

/// Close the sender
pub fn[T] Sender::close(self : Sender[T]) -> Unit {
  self.inner.state = Closed
  // Wake all receivers
  for coro in self.inner.receivers {
    coro.wake()
  }
  self.inner.receivers.clear()
}

/// Check if channel is closed
pub fn[T] Sender::is_closed(self : Sender[T]) -> Bool {
  self.inner.state is Closed
}

/// Receive a value from the channel
/// Blocks until a value is available or channel is closed
pub async fn[T] Receiver::recv(self : Receiver[T]) -> T? {
  while true {
    // Check buffer first
    if self.inner.buffer.length() > 0 {
      let value = self.inner.buffer.remove(0)
      // Wake a sender if waiting
      if self.inner.senders.length() > 0 {
        match self.inner.senders.pop() {
          Some(coro) => coro.wake()
          None => ()
        }
      }
      return Some(value)
    }

    // Buffer empty
    match self.inner.state {
      Closed => return None
      Open => {
        // Wait for data
        self.inner.receivers.push(@coroutine.current_coroutine())
        @coroutine.suspend()
      }
    }
  }
  None
}

/// Try to receive without blocking
pub fn[T] Receiver::try_recv(self : Receiver[T]) -> T? {
  if self.inner.buffer.length() > 0 {
    let value = self.inner.buffer.remove(0)
    if self.inner.senders.length() > 0 {
      match self.inner.senders.pop() {
        Some(coro) => coro.wake()
        None => ()
      }
    }
    Some(value)
  } else {
    None
  }
}

/// Check if channel has data available
pub fn[T] Receiver::is_ready(self : Receiver[T]) -> Bool {
  self.inner.buffer.length() > 0 || self.inner.state is Closed
}

/// Check if channel is closed
pub fn[T] Receiver::is_closed(self : Receiver[T]) -> Bool {
  self.inner.state is Closed && self.inner.buffer.length() == 0
}

/// Get number of buffered items
pub fn[T] Receiver::len(self : Receiver[T]) -> Int {
  self.inner.buffer.length()
}
