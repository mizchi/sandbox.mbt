/// Overlay filesystem
/// Layers a writable filesystem on top of a base filesystem
/// Writes go to the overlay, reads check overlay first then fall back to base

///|
/// Overlay filesystem that combines two filesystems
/// - Reads: check overlay first, fall back to base
/// - Writes: always go to overlay
/// - Deletes: mark as "whiteout" in overlay (file appears deleted)
pub struct OverlayFs {
  /// Base filesystem (typically read-only or host fs)
  base : &FileSystem
  /// Overlay filesystem (typically in-memory)
  overlay : Fs
  /// Tracks deleted paths (whiteouts)
  whiteouts : Map[String, Bool]
}

///|
/// Create a new overlay filesystem
pub fn OverlayFs::new(base : &FileSystem) -> OverlayFs {
  { base, overlay: Fs::default(), whiteouts: {} }
}

///|
/// Create with custom overlay options
pub fn OverlayFs::new_with_overlay(
  base : &FileSystem,
  overlay : Fs,
) -> OverlayFs {
  { base, overlay, whiteouts: {} }
}

///|
/// Check if path is marked as deleted (whiteout)
fn OverlayFs::is_whiteout(self : OverlayFs, path : String) -> Bool {
  self.whiteouts.get(path).unwrap_or(false)
}

///|
/// Mark path as deleted
fn OverlayFs::add_whiteout(self : OverlayFs, path : String) -> Unit {
  self.whiteouts[path] = true
}

///|
/// Remove whiteout marker
fn OverlayFs::remove_whiteout(self : OverlayFs, path : String) -> Unit {
  self.whiteouts.remove(path)
}

///|
/// Check if path exists in overlay
fn OverlayFs::in_overlay(self : OverlayFs, path : String) -> Bool {
  self.overlay.exists(path)
}

// ============ FileSystem Implementation ============

///|
pub impl FileSystem for OverlayFs with exists(self, path) {
  if self.is_whiteout(path) {
    false
  } else if self.in_overlay(path) {
    true
  } else {
    self.base.exists(path)
  }
}

///|
pub impl FileSystem for OverlayFs with is_dir(self, path) {
  if self.is_whiteout(path) {
    false
  } else if self.in_overlay(path) {
    self.overlay.is_dir(path)
  } else {
    self.base.is_dir(path)
  }
}

///|
pub impl FileSystem for OverlayFs with is_file(self, path) {
  if self.is_whiteout(path) {
    false
  } else if self.in_overlay(path) {
    self.overlay.is_file(path)
  } else {
    self.base.is_file(path)
  }
}

///|
pub impl FileSystem for OverlayFs with is_symlink(self, path) {
  if self.is_whiteout(path) {
    false
  } else if self.in_overlay(path) {
    self.overlay.is_symlink(path)
  } else {
    self.base.is_symlink(path)
  }
}

///|
pub impl FileSystem for OverlayFs with resolve_path(self, path) {
  if self.is_whiteout(path) {
    raise FsError::NotFound(path)
  } else if self.in_overlay(path) {
    self.overlay.resolve_path(path)
  } else {
    self.base.resolve_path(path)
  }
}

///|
pub impl FileSystem for OverlayFs with read_file(self, path) {
  if self.is_whiteout(path) {
    raise FsError::NotFound(path)
  } else if self.in_overlay(path) {
    self.overlay.read_file(path)
  } else {
    self.base.read_file(path)
  }
}

///|
pub impl FileSystem for OverlayFs with write_file(self, path, content) {
  // Remove whiteout if exists
  self.remove_whiteout(path)
  // Ensure parent directories exist in overlay
  ensure_parent_dirs(self, path)
  // Write to overlay
  self.overlay.write_file(path, content)
}

///|
pub impl FileSystem for OverlayFs with read_string(self, path) {
  if self.is_whiteout(path) {
    raise FsError::NotFound(path)
  } else if self.in_overlay(path) {
    self.overlay.read_string(path)
  } else {
    self.base.read_string(path)
  }
}

///|
pub impl FileSystem for OverlayFs with write_string(self, path, content) {
  self.remove_whiteout(path)
  ensure_parent_dirs(self, path)
  self.overlay.write_string(path, content)
}

///|
pub impl FileSystem for OverlayFs with truncate(self, path, length) {
  if self.is_whiteout(path) {
    raise FsError::NotFound(path)
  }
  // If file is in base but not overlay, copy to overlay first
  if !(self.in_overlay(path)) && self.base.exists(path) {
    let content = self.base.read_file(path)
    ensure_parent_dirs(self, path)
    self.overlay.write_file(path, content)
  }
  self.overlay.truncate(path, length)
}

///|
pub impl FileSystem for OverlayFs with size(self, path) {
  if self.is_whiteout(path) {
    None
  } else if self.in_overlay(path) {
    self.overlay.size(path)
  } else {
    self.base.size(path)
  }
}

///|
pub impl FileSystem for OverlayFs with remove(self, path) {
  if self.is_whiteout(path) {
    raise FsError::NotFound(path)
  }
  // Remove from overlay if present
  if self.in_overlay(path) {
    self.overlay.remove(path)
  }
  // If it exists in base, add whiteout
  if self.base.exists(path) {
    self.add_whiteout(path)
  }
}

///|
pub impl FileSystem for OverlayFs with mkdir(self, path) {
  if self.is_whiteout(path) {
    self.remove_whiteout(path)
  }
  if self.exists(path) {
    raise FsError::AlreadyExists(path)
  }
  ensure_parent_dirs(self, path)
  self.overlay.mkdir(path)
}

///|
pub impl FileSystem for OverlayFs with mkdir_p(self, path) {
  self.remove_whiteout(path)
  // Create each component
  let parts = path.split("/").filter(fn(p) { p.to_string().length() > 0 })
  let mut current = ""
  for part in parts {
    current = current + "/" + part.to_string()
    self.remove_whiteout(current)
    if !(self.exists(current)) {
      self.overlay.mkdir(current)
    }
  }
}

///|
pub impl FileSystem for OverlayFs with rmdir(self, path) {
  if self.is_whiteout(path) {
    raise FsError::NotFound(path)
  }
  if !(self.is_dir(path)) {
    raise FsError::NotADirectory(path)
  }
  // Remove from overlay if present
  if self.in_overlay(path) {
    self.overlay.rmdir(path)
  }
  // Add whiteout if exists in base
  if self.base.exists(path) {
    self.add_whiteout(path)
  }
}

///|
pub impl FileSystem for OverlayFs with readdir(self, path) {
  if self.is_whiteout(path) {
    raise FsError::NotFound(path)
  }
  // Merge entries from overlay and base
  let entries : Map[String, Bool] = {}
  // Add overlay entries
  if self.overlay.is_dir(path) {
    for entry in self.overlay.readdir(path) {
      let full_path = if path == "/" { "/" + entry } else { path + "/" + entry }
      if !(self.is_whiteout(full_path)) {
        entries[entry] = true
      }
    }
  }
  // Add base entries (if not already in overlay or whiteout)
  if self.base.is_dir(path) {
    for entry in self.base.readdir(path) {
      let full_path = if path == "/" { "/" + entry } else { path + "/" + entry }
      if !(self.is_whiteout(full_path)) && !(entries.contains(entry)) {
        entries[entry] = true
      }
    }
  }
  entries.keys().collect()
}

///|
pub impl FileSystem for OverlayFs with symlink(self, path, target) {
  self.remove_whiteout(path)
  ensure_parent_dirs(self, path)
  self.overlay.symlink(path, target)
}

///|
pub impl FileSystem for OverlayFs with read_link(self, path) {
  if self.is_whiteout(path) {
    raise FsError::NotFound(path)
  } else if self.in_overlay(path) {
    self.overlay.read_link(path)
  } else {
    self.base.read_link(path)
  }
}

///|
pub impl FileSystem for OverlayFs with rename(self, old_path, new_path) {
  if self.is_whiteout(old_path) {
    raise FsError::NotFound(old_path)
  }
  // Read from wherever it exists
  if self.is_dir(old_path) {
    // For directories, need to move all contents
    self.mkdir_p(new_path)
    for entry in self.readdir(old_path) {
      let old_entry = if old_path == "/" {
        "/" + entry
      } else {
        old_path + "/" + entry
      }
      let new_entry = if new_path == "/" {
        "/" + entry
      } else {
        new_path + "/" + entry
      }
      self.rename(old_entry, new_entry)
    }
    self.rmdir(old_path)
  } else {
    // For files, copy content then remove
    let content = self.read_file(old_path)
    self.write_file(new_path, content)
    self.remove(old_path)
  }
}

///|
pub impl FileSystem for OverlayFs with stat(self, path) {
  if self.is_whiteout(path) {
    raise FsError::NotFound(path)
  } else if self.in_overlay(path) {
    self.overlay.stat(path)
  } else {
    self.base.stat(path)
  }
}

// ============ Helper Functions ============

///|
/// Ensure parent directories exist in overlay
fn ensure_parent_dirs(fs : OverlayFs, path : String) -> Unit {
  let parts : Array[String] = path
    .split("/")
    .filter(fn(p) { p.to_string().length() > 0 })
    .map(fn(p) { p.to_string() })
    .collect()
  if parts.length() <= 1 {
    return
  }
  let mut current = ""
  for i = 0; i < parts.length() - 1; i = i + 1 {
    current = current + "/" + parts[i]
    if !(fs.overlay.exists(current)) {
      fs.overlay.mkdir(current) catch {
        _ => () // Directory might already exist
      }
    }
  }
}

// ============ Utility Methods ============

///|
/// Get list of all whiteouts (for debugging)
pub fn OverlayFs::get_whiteouts(self : OverlayFs) -> Array[String] {
  self.whiteouts.keys().collect()
}

///|
/// Clear all whiteouts
pub fn OverlayFs::clear_whiteouts(self : OverlayFs) -> Unit {
  self.whiteouts.clear()
}

///|
/// Get the overlay filesystem directly
pub fn OverlayFs::get_overlay(self : OverlayFs) -> Fs {
  self.overlay
}

///|
/// Check if a path has been modified in overlay
pub fn OverlayFs::is_modified(self : OverlayFs, path : String) -> Bool {
  self.in_overlay(path) || self.is_whiteout(path)
}

///|
/// Get all modified paths
pub fn OverlayFs::get_modified_paths(self : OverlayFs) -> Array[String] {
  let paths : Map[String, Bool] = {}
  // Add all overlay entries
  fn collect_paths(fs : Fs, dir : String, paths : Map[String, Bool]) -> Unit {
    if fs.is_dir(dir) {
      try {
        for entry in fs.readdir(dir) {
          let path = if dir == "/" { "/" + entry } else { dir + "/" + entry }
          paths[path] = true
          collect_paths(fs, path, paths)
        }
      } catch {
        _ => ()
      }
    }
  }
  collect_paths(self.overlay, "/", paths)
  // Add whiteouts
  for path in self.whiteouts.keys() {
    paths[path] = true
  }
  paths.keys().collect()
}
