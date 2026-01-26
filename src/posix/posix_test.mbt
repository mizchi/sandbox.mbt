// Tests for POSIX Context

test "open and close file" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")

  let fd = ctx.open("/test.txt", OpenFlags::from([O_RDONLY]), FileMode::default_file())
  assert_true(fd.to_int() >= 3)

  ctx.close(fd)
}

test "open with O_CREAT" {
  let ctx = PosixContext::default()

  let fd = ctx.open("/new.txt", OpenFlags::from([O_WRONLY, O_CREAT]), FileMode::default_file())
  ctx.close(fd)

  assert_true(ctx.get_fs().exists("/new.txt"))
}

test "open nonexistent without O_CREAT fails" {
  let ctx = PosixContext::default()

  let result : Result[Fd, _] = try { Ok(ctx.open("/nonexistent.txt", OpenFlags::from([O_RDONLY]), FileMode::default_file())) } catch {
    e => Err(e)
  }

  assert_true(result is Err(_))
}

test "read and write" {
  let ctx = PosixContext::default()

  let fd = ctx.open("/test.txt", OpenFlags::from([O_RDWR, O_CREAT]), FileMode::default_file())

  let written = ctx.write(fd, Bytes::from_array([b'h', b'i']))
  assert_eq(written, 2)

  // Seek back to start
  let _ = ctx.lseek(fd, 0L, SEEK_SET)

  let data = ctx.read(fd, 10)
  assert_eq(data.length(), 2)
  assert_eq(data[0], b'h')
  assert_eq(data[1], b'i')

  ctx.close(fd)
}

test "lseek" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello world")

  let fd = ctx.open("/test.txt", OpenFlags::from([O_RDONLY]), FileMode::default_file())

  // Seek from start
  let pos1 = ctx.lseek(fd, 6L, SEEK_SET)
  assert_eq(pos1, 6L)

  // Seek from current
  let pos2 = ctx.lseek(fd, 2L, SEEK_CUR)
  assert_eq(pos2, 8L)

  // Seek from end
  let pos3 = ctx.lseek(fd, -5L, SEEK_END)
  assert_eq(pos3, 6L)

  ctx.close(fd)
}

test "dup" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")

  let fd1 = ctx.open("/test.txt", OpenFlags::from([O_RDONLY]), FileMode::default_file())
  let fd2 = ctx.dup(fd1)

  assert_true(fd1.to_int() != fd2.to_int())

  // Both can read
  let data1 = ctx.read(fd1, 2)
  assert_eq(data1.length(), 2)

  // fd2 has its own offset
  let data2 = ctx.read(fd2, 2)
  assert_eq(data2.length(), 2)

  ctx.close(fd1)
  ctx.close(fd2)
}

test "pipe" {
  let ctx = PosixContext::default()

  let pipe_fds = ctx.pipe()

  // Write to write end
  let written = ctx.write(pipe_fds.write_fd, Bytes::from_array([b'a', b'b', b'c']))
  assert_eq(written, 3)

  // Read from read end
  let data = ctx.read(pipe_fds.read_fd, 10)
  assert_eq(data.length(), 3)
  assert_eq(data[0], b'a')

  ctx.close(pipe_fds.read_fd)
  ctx.close(pipe_fds.write_fd)
}

test "stat" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")
  ctx.get_fs().mkdir("/dir")

  let file_stat = ctx.stat("/test.txt")
  assert_true(file_stat.is_file())
  assert_eq(file_stat.st_size, 5L)

  let dir_stat = ctx.stat("/dir")
  assert_true(dir_stat.is_dir())
}

test "fstat" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")

  let fd = ctx.open("/test.txt", OpenFlags::from([O_RDONLY]), FileMode::default_file())
  let stat = ctx.fstat(fd)

  assert_true(stat.is_file())
  assert_eq(stat.st_size, 5L)

  ctx.close(fd)
}

test "lstat for symlink" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/target.txt", "content")
  ctx.get_fs().symlink("/link.txt", "target.txt")

  let lstat_result = ctx.lstat("/link.txt")
  assert_true(lstat_result.is_symlink())

  let stat_result = ctx.stat("/link.txt")
  assert_true(stat_result.is_file())
}

test "environment variables" {
  let ctx = PosixContext::default()

  assert_eq(ctx.getenv("HOME"), Some("/home"))
  assert_eq(ctx.getenv("NONEXISTENT"), None)

  ctx.setenv("MY_VAR", "my_value")
  assert_eq(ctx.getenv("MY_VAR"), Some("my_value"))

  ctx.unsetenv("MY_VAR")
  assert_eq(ctx.getenv("MY_VAR"), None)
}

test "getcwd and chdir" {
  let ctx = PosixContext::default()
  ctx.get_fs().mkdir("/subdir")

  assert_eq(ctx.getcwd(), "/")

  ctx.chdir("/subdir")
  assert_eq(ctx.getcwd(), "/subdir")
  assert_eq(ctx.getenv("PWD"), Some("/subdir"))
}

test "resolve_path" {
  let ctx = PosixContext::default()
  ctx.get_fs().mkdir("/a")
  ctx.get_fs().mkdir("/a/b")

  // Absolute path
  assert_eq(ctx.resolve_path("/a/b"), "/a/b")

  // Relative path
  ctx.chdir("/a")
  assert_eq(ctx.resolve_path("b"), "/a/b")

  // With dots
  assert_eq(ctx.resolve_path("./b"), "/a/b")
  assert_eq(ctx.resolve_path("../a/b"), "/a/b")

  // Home
  assert_eq(ctx.resolve_path("~"), "/home")
}

test "getuid and friends" {
  let ctx = PosixContext::default()

  assert_eq(ctx.getuid(), 1000)
  assert_eq(ctx.geteuid(), 1000)
  assert_eq(ctx.getgid(), 1000)
  assert_eq(ctx.getegid(), 1000)
}

test "getpid" {
  let ctx = PosixContext::default()
  let pid = ctx.getpid()
  assert_eq(pid.to_int(), 1)
}

test "spawn and waitpid" {
  let ctx = PosixContext::default()

  let pid = ctx.spawn("/bin/echo", ["hello"])
  assert_true(pid.to_int() > 1)
  assert_true(ctx.process_running(pid))

  // Simulate process exit
  ctx.process_exit(pid, 0)
  assert_false(ctx.process_running(pid))
  assert_eq(ctx.waitpid(pid), Some(0))
}

test "mock time" {
  let ctx = PosixContext::default()

  ctx.set_mock_time(1234567890000L)
  assert_eq(ctx.get_time(), 1234567890000L)
  assert_eq(ctx.time(), 1234567890L)

  let ts = ctx.clock_gettime(CLOCK_REALTIME)
  assert_eq(ts.tv_sec, 1234567890L)
}

test "standard file descriptors exist" {
  let ctx = PosixContext::default()

  // stdin, stdout, stderr should exist
  let stdin_stat = ctx.fstat(stdin_fileno())
  let stdout_stat = ctx.fstat(stdout_fileno())
  let stderr_stat = ctx.fstat(stderr_fileno())

  // They should all be valid
  ignore(stdin_stat)
  ignore(stdout_stat)
  ignore(stderr_stat)
}

// ============ Phase A: fcntl tests ============

test "fcntl F_GETFL and F_SETFL" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")

  let fd = ctx.open("/test.txt", OpenFlags::from([O_RDONLY]), FileMode::default_file())

  // Get current flags
  let flags = ctx.fcntl_getfl(fd)
  assert_true(flags.has(O_RDONLY))
  assert_false(flags.has(O_NONBLOCK))

  // Set O_NONBLOCK
  ctx.fcntl_setfl(fd, flags.add(O_NONBLOCK))

  // Verify it's set
  let new_flags = ctx.fcntl_getfl(fd)
  assert_true(new_flags.has(O_NONBLOCK))

  ctx.close(fd)
}

test "fcntl F_DUPFD" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")

  let fd1 = ctx.open("/test.txt", OpenFlags::from([O_RDONLY]), FileMode::default_file())

  // Duplicate to fd >= 10
  let fd2 = ctx.fcntl_dupfd(fd1, 10)
  assert_true(fd2.to_int() >= 10)

  // Both should be able to read
  let data1 = ctx.read(fd1, 5)
  assert_eq(data1.length(), 5)

  ctx.close(fd1)
  ctx.close(fd2)
}

// ============ Phase A: poll tests ============

test "poll on pipe - write ready" {
  let ctx = PosixContext::default()
  let pipe = ctx.pipe()

  // Poll for write readiness
  let pollfds = [PollFd::new(pipe.write_fd, POLLOUT)]
  let ready = ctx.poll(pollfds, 0)

  assert_eq(ready, 1)
  assert_true(pollfds[0].has_revent(POLLOUT))

  ctx.close(pipe.read_fd)
  ctx.close(pipe.write_fd)
}

test "poll on pipe - read ready after write" {
  let ctx = PosixContext::default()
  let pipe = ctx.pipe()

  // Write some data
  let _ = ctx.write(pipe.write_fd, Bytes::from_array([b'a', b'b']))

  // Poll for read readiness
  let pollfds = [PollFd::new(pipe.read_fd, POLLIN)]
  let ready = ctx.poll(pollfds, 0)

  assert_eq(ready, 1)
  assert_true(pollfds[0].has_revent(POLLIN))

  ctx.close(pipe.read_fd)
  ctx.close(pipe.write_fd)
}

test "poll on pipe - read not ready when empty" {
  let ctx = PosixContext::default()
  let pipe = ctx.pipe()

  // Poll for read readiness (nothing written yet)
  let pollfds = [PollFd::new(pipe.read_fd, POLLIN)]
  let ready = ctx.poll(pollfds, 0)  // timeout=0 means don't block

  assert_eq(ready, 0)
  assert_false(pollfds[0].has_revent(POLLIN))

  ctx.close(pipe.read_fd)
  ctx.close(pipe.write_fd)
}

test "poll on file - always ready" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")

  let fd = ctx.open("/test.txt", OpenFlags::from([O_RDONLY]), FileMode::default_file())

  // Regular files are always ready for reading
  let pollfds = [PollFd::new(fd, POLLIN)]
  let ready = ctx.poll(pollfds, 0)

  assert_eq(ready, 1)
  assert_true(pollfds[0].has_revent(POLLIN))

  ctx.close(fd)
}

test "poll multiple fds" {
  let ctx = PosixContext::default()
  let pipe1 = ctx.pipe()
  let pipe2 = ctx.pipe()

  // Write to pipe2 only
  let _ = ctx.write(pipe2.write_fd, Bytes::from_array([b'x']))

  // Poll both pipes for read
  let pollfds = [
    PollFd::new(pipe1.read_fd, POLLIN),
    PollFd::new(pipe2.read_fd, POLLIN),
  ]
  let ready = ctx.poll(pollfds, 0)

  assert_eq(ready, 1)
  assert_false(pollfds[0].has_revent(POLLIN))  // pipe1 not ready
  assert_true(pollfds[1].has_revent(POLLIN))   // pipe2 ready

  ctx.close(pipe1.read_fd)
  ctx.close(pipe1.write_fd)
  ctx.close(pipe2.read_fd)
  ctx.close(pipe2.write_fd)
}

test "poll bad fd" {
  let ctx = PosixContext::default()

  let pollfds = [PollFd::new(Fd::from_int(999), POLLIN)]
  let ready = ctx.poll(pollfds, 0)

  assert_eq(ready, 1)
  assert_true(pollfds[0].has_revent(POLLNVAL))
}

// ============ Phase B: access tests ============

test "access file exists and readable" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello")

  // F_OK - file exists (should not raise)
  ctx.access("/test.txt", F_OK)

  // R_OK - readable
  ctx.access("/test.txt", R_OK)

  // W_OK - writable
  ctx.access("/test.txt", W_OK)
}

test "access nonexistent file" {
  let ctx = PosixContext::default()

  let result : Result[Unit, _] = try {
    ctx.access("/nonexistent.txt", F_OK)
    Ok(())
  } catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

test "access directory" {
  let ctx = PosixContext::default()
  ctx.get_fs().mkdir("/mydir")

  ctx.access("/mydir", F_OK)
  ctx.access("/mydir", R_OK)
  ctx.access("/mydir", X_OK)  // directories are executable (searchable)
}

// ============ Phase B: rename tests ============

test "rename file" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/old.txt", "content")

  ctx.rename("/old.txt", "/new.txt")

  assert_false(ctx.get_fs().exists("/old.txt"))
  assert_true(ctx.get_fs().exists("/new.txt"))
  assert_eq(ctx.get_fs().read_string("/new.txt"), "content")
}

test "rename file overwrite" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/src.txt", "new content")
  ctx.get_fs().write_string("/dst.txt", "old content")

  ctx.rename("/src.txt", "/dst.txt")

  assert_false(ctx.get_fs().exists("/src.txt"))
  assert_eq(ctx.get_fs().read_string("/dst.txt"), "new content")
}

test "rename directory" {
  let ctx = PosixContext::default()
  ctx.get_fs().mkdir("/olddir")
  ctx.get_fs().write_string("/olddir/file.txt", "data")

  ctx.rename("/olddir", "/newdir")

  assert_false(ctx.get_fs().exists("/olddir"))
  assert_true(ctx.get_fs().is_dir("/newdir"))
  assert_eq(ctx.get_fs().read_string("/newdir/file.txt"), "data")
}

// ============ Phase B: truncate tests ============

test "truncate file" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello world")

  ctx.truncate("/test.txt", 5L)

  assert_eq(ctx.get_fs().read_string("/test.txt"), "hello")
}

test "truncate file extend" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hi")

  ctx.truncate("/test.txt", 5L)

  let content = ctx.get_fs().read_file("/test.txt")
  assert_eq(content.length(), 5)
  assert_eq(content[0], b'h')
  assert_eq(content[1], b'i')
  assert_eq(content[2], b'\x00')  // Extended with null bytes
}

test "ftruncate" {
  let ctx = PosixContext::default()
  ctx.get_fs().write_string("/test.txt", "hello world")

  let fd = ctx.open("/test.txt", OpenFlags::from([O_RDWR]), FileMode::default_file())
  ctx.ftruncate(fd, 5L)
  ctx.close(fd)

  assert_eq(ctx.get_fs().read_string("/test.txt"), "hello")
}
