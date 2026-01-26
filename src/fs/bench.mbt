///|
/// Benchmarks for MemFS

///|
test "bench: MemFS write small file" (b : @bench.T) {
  let fs = MemFS::new()
  let result = b.bench(fn() {
    fs.write_string("/test.txt", "hello world") catch {
      _ => ()
    }
  })
  b.keep(result)
}

///|
test "bench: MemFS write large file" (b : @bench.T) {
  let fs = MemFS::new()
  let data = String::make(1024 * 10, 'x') // 10KB
  let result = b.bench(fn() {
    fs.write_string("/large.txt", data) catch {
      _ => ()
    }
  })
  b.keep(result)
}

///|
test "bench: MemFS read file" (b : @bench.T) {
  let fs = MemFS::new()
  fs.write_string("/test.txt", "hello world")
  let result = b.bench(fn() {
    let _ = fs.read_string("/test.txt") catch { _ => "" }

  })
  b.keep(result)
}

///|
test "bench: MemFS mkdir" (b : @bench.T) {
  let fs = MemFS::new()
  let mut i = 0
  let result = b.bench(fn() {
    fs.mkdir("/dir" + i.to_string()) catch {
      _ => ()
    }
    i = i + 1
  })
  b.keep(result)
}

///|
test "bench: MemFS exists check" (b : @bench.T) {
  let fs = MemFS::new()
  fs.write_string("/test.txt", "hello")
  let result = b.bench(fn() {
    let _ = fs.exists("/test.txt")

  })
  b.keep(result)
}

///|
test "bench: MemFS path resolution" (b : @bench.T) {
  let fs = MemFS::new()
  fs.mkdir("/a")
  fs.mkdir("/a/b")
  fs.mkdir("/a/b/c")
  fs.write_string("/a/b/c/file.txt", "data")
  let result = b.bench(fn() {
    let _ = fs.resolve_path("/a/b/../b/c/./file.txt") catch { _ => "" }

  })
  b.keep(result)
}

///|
test "bench: MemFS rename file" (b : @bench.T) {
  let fs = MemFS::new()
  let mut i = 0
  let result = b.bench(fn() {
    let old_name = "/f" + i.to_string() + ".txt"
    let new_name = "/g" + i.to_string() + ".txt"
    try {
      fs.write_string(old_name, "data")
      fs.rename(old_name, new_name)
    } catch {
      _ => ()
    }
    i = i + 1
  })
  b.keep(result)
}

///|
test "bench: MemFS truncate shrink" (b : @bench.T) {
  let fs = MemFS::new()
  fs.write_string("/test.txt", "hello world this is test data")
  let result = b.bench(fn() {
    try {
      fs.truncate("/test.txt", 10)
      // Restore for next iteration
      fs.truncate("/test.txt", 30)
    } catch {
      _ => ()
    }
  })
  b.keep(result)
}
