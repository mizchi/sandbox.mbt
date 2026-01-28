///| Internal stub to keep imports used across targets

///|
fn _use_deps() -> Unit {
  let _ = @git.ObjectId::zero()
  let _ = @runtime.Command::new("git-upload-pack")
  let _ = @fs.Fs::default()
}
