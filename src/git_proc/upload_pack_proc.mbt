///| Upload-pack over SSH/file (native targets, via git-upload-pack)

///|
pub fn upload_pack_info_refs_proc(
  backend : &@runtime.ProcessManager,
  remote : String,
  prefer_v2 : Bool,
) -> Bytes raise @git.GitError {
  let spec = @git.parse_remote(remote)
  let cmd = build_upload_pack_command(spec, true, prefer_v2)
  run_upload_pack(backend, cmd, Bytes::new(0))
}

///|
pub fn upload_pack_request_proc(
  backend : &@runtime.ProcessManager,
  remote : String,
  body : Bytes,
  prefer_v2 : Bool,
) -> Bytes raise @git.GitError {
  let spec = @git.parse_remote(remote)
  let cmd = build_upload_pack_command(spec, false, prefer_v2)
  run_upload_pack(backend, cmd, body)
}

///|
pub fn discover_upload_refs_proc(
  backend : &@runtime.ProcessManager,
  remote : String,
  prefer_v2 : Bool,
) -> (Array[(@git.ObjectId, String)], Array[String], @git.ProtocolVersion, Map[String, String]) raise @git.GitError {
  let adv = upload_pack_info_refs_proc(backend, remote, prefer_v2)
  let version = @git.detect_protocol_version(adv)
  if version == @git.ProtocolVersion::V2 {
    let caps = @git.parse_v2_advertised_caps(adv)
    let req = @git.build_ls_refs_request(
      "git/moonbit",
      ["refs/heads/", "refs/tags/", "HEAD"],
    )
    let resp = upload_pack_request_proc(backend, remote, req, true)
    let parsed = @git.parse_ls_refs_response(resp)
    return (parsed.refs, caps, version, parsed.symrefs)
  }
  let refs = @git.parse_refs(adv)
  let caps = @git.parse_v0_advertised_caps(adv)
  (refs, caps, @git.ProtocolVersion::V0, {})
}

///|
pub fn fetch_pack_proc(
  backend : &@runtime.ProcessManager,
  remote : String,
  wants : Array[@git.ObjectId],
  prefer_v2 : Bool,
) -> Bytes raise @git.GitError {
  let (refs, caps, version, _symrefs) = discover_upload_refs_proc(
    backend,
    remote,
    prefer_v2,
  )
  let wants = if wants.length() == 0 {
    let ids : Array[@git.ObjectId] = []
    for item in refs {
      let (id, _) = item
      ids.push(id)
    }
    ids
  } else {
    wants
  }
  if version == @git.ProtocolVersion::V2 {
    let req = @git.build_fetch_request_v2("git/moonbit", wants)
    let resp = upload_pack_request_proc(backend, remote, req, true)
    return @git.extract_pack_from_v2_response(resp)
  }
  let req = @git.build_fetch_request_v0("git/moonbit", wants, caps)
  let resp = upload_pack_request_proc(backend, remote, req, false)
  @git.extract_pack_from_v0_response(resp)
}

///|
pub fn fetch_objects_proc(
  backend : &@runtime.ProcessManager,
  remote : String,
  wants : Array[@git.ObjectId],
  prefer_v2 : Bool,
) -> Array[@git.PackObject] raise @git.GitError {
  let pack = fetch_pack_proc(backend, remote, wants, prefer_v2)
  @git.parse_packfile(pack)
}

///|
pub fn clone_proc(
  backend : &@runtime.ProcessManager,
  remote : String,
  prefer_v2 : Bool,
) -> (Array[(@git.ObjectId, String)], Array[@git.PackObject]) raise @git.GitError {
  let (refs, _caps, _version, symrefs) = discover_upload_refs_proc(
    backend,
    remote,
    prefer_v2,
  )
  let wants = @git.select_default_wants(refs, symrefs)
  let pack = fetch_pack_proc(backend, remote, wants, prefer_v2)
  let objects = @git.parse_packfile(pack)
  (refs, objects)
}

///|
pub fn clone_proc_to_fs(
  backend : &@runtime.ProcessManager,
  remote : String,
  prefer_v2 : Bool,
  fs : &@fs.FileSystem,
  root : String,
) -> Array[(@git.ObjectId, String)] raise @git.GitError {
  let (refs, _caps, _version, symrefs) = discover_upload_refs_proc(
    backend,
    remote,
    prefer_v2,
  )
  let wants = @git.select_default_wants(refs, symrefs)
  let default_ref = @git.select_default_ref(refs, symrefs)
  match default_ref {
    None => return refs
    Some(_) => ()
  }
  if wants.length() == 0 {
    return refs
  }
  let pack = fetch_pack_proc(backend, remote, wants, prefer_v2)
  let objects = @git.parse_packfile(pack)
  let store = @git.ObjectStore::from_pack(objects)
  match default_ref {
    None => ()
    Some((refname, commit_id)) =>
      @git.materialize_clone_to_fs(store, commit_id, refname, remote, fs, root)
  }
  refs
}

///|
fn build_upload_pack_command(
  spec : @git.RemoteSpec,
  advertise : Bool,
  prefer_v2 : Bool,
) -> @runtime.Command raise @git.GitError {
  if spec.kind != @git.RemoteKind::Http && spec.path.length() == 0 {
    raise @git.GitError::ProtocolError("Remote path is required")
  }
  let subcmd = build_upload_pack_subcommand(spec.path, advertise)
  match spec.kind {
    @git.RemoteKind::File => {
      let mut cmd = @runtime.Command::new("git-upload-pack")
        .args(subcmd)
        .stdin(@runtime.Stdio::Piped)
        .stdout(@runtime.Stdio::Piped)
        .stderr(@runtime.Stdio::Piped)
      if prefer_v2 {
        cmd = cmd.env("GIT_PROTOCOL", "version=2")
      }
      return cmd
    }
    @git.RemoteKind::Ssh => {
      let host = spec.host.unwrap_or("")
      let (host_only, port) = split_ssh_host(host)
      if host_only.length() == 0 {
        raise @git.GitError::ProtocolError("SSH remote missing host")
      }
      let ssh_args : Array[String] = []
      match port {
        Some(p) => {
          ssh_args.push("-p")
          ssh_args.push(p)
        }
        None => ()
      }
      ssh_args.push(host_only)
      ssh_args.push(build_ssh_remote_command(subcmd, prefer_v2))
      let cmd = @runtime.Command::new("ssh")
        .args(ssh_args)
        .stdin(@runtime.Stdio::Piped)
        .stdout(@runtime.Stdio::Piped)
        .stderr(@runtime.Stdio::Piped)
      return cmd
    }
    @git.RemoteKind::Http =>
      raise @git.GitError::ProtocolError("HTTP transport not available in proc mode")
  }
}

///|
fn build_upload_pack_subcommand(
  path : String,
  advertise : Bool,
) -> Array[String] {
  let args : Array[String] = ["--stateless-rpc"]
  if advertise {
    args.push("--advertise-refs")
  }
  args.push(path)
  args
}

///|
fn build_ssh_remote_command(
  subcmd : Array[String],
  prefer_v2 : Bool,
) -> String {
  let cmd = subcmd.join(" ")
  if prefer_v2 {
    "GIT_PROTOCOL=version=2 git-upload-pack \{cmd}"
  } else {
    "git-upload-pack \{cmd}"
  }
}

///|
fn split_ssh_host(host : String) -> (String, String?) {
  let idx = host.find(":")
  match idx {
    None => (host, None)
    Some(i) => {
      let h = String::unsafe_substring(host, start=0, end=i)
      let p = String::unsafe_substring(host, start=i + 1, end=host.length())
      if p.length() == 0 {
        (host, None)
      } else {
        (h, Some(p))
      }
    }
  }
}

///|
fn run_upload_pack(
  backend : &@runtime.ProcessManager,
  cmd : @runtime.Command,
  input : Bytes,
) -> Bytes raise @git.GitError {
  let proc = backend.spawn(cmd) catch {
    e => raise @git.GitError::IoError("spawn failed: \{e}")
  }
  let pid = proc.pid()
  if input.length() > 0 {
    backend.write_stdin_bytes(pid, input) catch {
      e => raise @git.GitError::IoError("stdin write failed: \{e}")
    }
  }
  backend.close_stdin(pid) catch {
    e => raise @git.GitError::IoError("stdin close failed: \{e}")
  }
  let status = backend.wait(pid) catch {
    e => raise @git.GitError::IoError("wait failed: \{e}")
  }
  let stdout = backend.read_stdout_bytes(pid) catch {
    e => raise @git.GitError::IoError("stdout read failed: \{e}")
  }
  let stderr = backend.read_stderr_bytes(pid) catch {
    _ => Bytes::new(0)
  }
  if not(status.is_success()) {
    let msg = bytes_to_string(stderr)
    raise @git.GitError::ProtocolError("upload-pack failed: \{msg}")
  }
  stdout
}

///|
fn bytes_to_string(data : Bytes) -> String {
  let result = StringBuilder::new()
  for b in data {
    result.write_char(b.to_int().unsafe_to_char())
  }
  result.to_string()
}
