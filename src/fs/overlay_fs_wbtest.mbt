/// Tests for OverlayFs

///|
test "OverlayFs reads from base" {
  let base = Fs::default()
  base.write_string("/base.txt", "from base")
  let overlay = OverlayFs::new(base)
  assert_eq(overlay.read_string("/base.txt"), "from base")
}

///|
test "OverlayFs writes to overlay" {
  let base = Fs::default()
  base.write_string("/base.txt", "from base")
  let overlay = OverlayFs::new(base)

  // Write to overlay
  overlay.write_string("/new.txt", "new content")

  // Should be readable
  assert_eq(overlay.read_string("/new.txt"), "new content")

  // Base should not have it
  assert_false(base.exists("/new.txt"))
}

///|
test "OverlayFs overlay shadows base" {
  let base = Fs::default()
  base.write_string("/file.txt", "base content")
  let overlay = OverlayFs::new(base)

  // Overwrite in overlay
  overlay.write_string("/file.txt", "overlay content")

  // Should read overlay version
  assert_eq(overlay.read_string("/file.txt"), "overlay content")

  // Base unchanged
  assert_eq(base.read_string("/file.txt"), "base content")
}

///|
test "OverlayFs delete creates whiteout" {
  let base = Fs::default()
  base.write_string("/file.txt", "content")
  let overlay = OverlayFs::new(base)

  // Delete file
  overlay.remove("/file.txt")

  // Should not exist in overlay view
  assert_false(overlay.exists("/file.txt"))

  // But still exists in base
  assert_true(base.exists("/file.txt"))

  // Whiteout should be tracked
  assert_true(overlay.get_whiteouts().contains("/file.txt"))
}

///|
test "OverlayFs recreate after delete" {
  let base = Fs::default()
  base.write_string("/file.txt", "original")
  let overlay = OverlayFs::new(base)

  // Delete
  overlay.remove("/file.txt")
  assert_false(overlay.exists("/file.txt"))

  // Recreate
  overlay.write_string("/file.txt", "recreated")
  assert_true(overlay.exists("/file.txt"))
  assert_eq(overlay.read_string("/file.txt"), "recreated")

  // Whiteout should be removed
  assert_false(overlay.get_whiteouts().contains("/file.txt"))
}

///|
test "OverlayFs readdir merges entries" {
  let base = Fs::default()
  base.mkdir("/dir")
  base.write_string("/dir/base1.txt", "1")
  base.write_string("/dir/base2.txt", "2")

  let overlay = OverlayFs::new(base)
  overlay.write_string("/dir/overlay1.txt", "3")

  let entries = overlay.readdir("/dir")
  assert_true(entries.contains("base1.txt"))
  assert_true(entries.contains("base2.txt"))
  assert_true(entries.contains("overlay1.txt"))
}

///|
test "OverlayFs readdir excludes whiteouts" {
  let base = Fs::default()
  base.mkdir("/dir")
  base.write_string("/dir/keep.txt", "keep")
  base.write_string("/dir/delete.txt", "delete")

  let overlay = OverlayFs::new(base)
  overlay.remove("/dir/delete.txt")

  let entries = overlay.readdir("/dir")
  assert_true(entries.contains("keep.txt"))
  assert_false(entries.contains("delete.txt"))
}

///|
test "OverlayFs mkdir creates in overlay" {
  let base = Fs::default()
  let overlay = OverlayFs::new(base)

  overlay.mkdir("/newdir")
  assert_true(overlay.is_dir("/newdir"))
  assert_false(base.exists("/newdir"))
}

///|
test "OverlayFs is_modified tracks changes" {
  let base = Fs::default()
  base.write_string("/base.txt", "base")

  let overlay = OverlayFs::new(base)

  // Initially not modified
  assert_false(overlay.is_modified("/base.txt"))

  // After write
  overlay.write_string("/new.txt", "new")
  assert_true(overlay.is_modified("/new.txt"))

  // After delete
  overlay.remove("/base.txt")
  assert_true(overlay.is_modified("/base.txt"))
}

///|
test "OverlayFs nested directory creation" {
  let base = Fs::default()
  let overlay = OverlayFs::new(base)

  // Write to deep path should create parent dirs
  overlay.write_string("/a/b/c/file.txt", "deep")

  assert_true(overlay.is_dir("/a"))
  assert_true(overlay.is_dir("/a/b"))
  assert_true(overlay.is_dir("/a/b/c"))
  assert_eq(overlay.read_string("/a/b/c/file.txt"), "deep")
}
