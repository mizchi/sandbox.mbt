/// CLI argument parser for Deno-like permissions

/// Parse result
pub struct ParsedArgs {
  permissions : Permissions
  program_args : Array[String]
}

/// Parse CLI arguments into permissions and program args
///
/// Supported flags:
/// - --allow-read[=path]
/// - --allow-write[=path]
/// - --allow-net[=host]
/// - --allow-env[=var]
/// - --allow-run[=cmd]
/// - --allow-all
/// - --deny-read[=path]
/// - --deny-write[=path]
/// - --deny-net[=host]
/// - --deny-env[=var]
/// - --deny-run[=cmd]
pub fn parse_args(args : Array[String]) -> ParsedArgs {
  let permissions = Permissions::new()
  let program_args : Array[String] = []
  let mut i = 0

  while i < args.length() {
    let arg = args[i]

    if arg == "--allow-all" {
      permissions.allow(PermissionDescriptor::Read(path=None))
      permissions.allow(PermissionDescriptor::Write(path=None))
      permissions.allow(PermissionDescriptor::Net(host=None))
      permissions.allow(PermissionDescriptor::Env(variable=None))
      permissions.allow(PermissionDescriptor::Run(command=None))
      i += 1
      continue
    }

    if arg == "--" {
      // Everything after -- is program args
      i += 1
      while i < args.length() {
        program_args.push(args[i])
        i += 1
      }
      break
    }

    // Parse --allow-* flags
    if arg.has_prefix("--allow-read") {
      let path = parse_flag_value(arg, "--allow-read")
      permissions.allow(PermissionDescriptor::Read(path~))
      i += 1
      continue
    }

    if arg.has_prefix("--allow-write") {
      let path = parse_flag_value(arg, "--allow-write")
      permissions.allow(PermissionDescriptor::Write(path~))
      i += 1
      continue
    }

    if arg.has_prefix("--allow-net") {
      let host = parse_flag_value(arg, "--allow-net")
      permissions.allow(PermissionDescriptor::Net(host~))
      i += 1
      continue
    }

    if arg.has_prefix("--allow-env") {
      let variable = parse_flag_value(arg, "--allow-env")
      permissions.allow(PermissionDescriptor::Env(variable~))
      i += 1
      continue
    }

    if arg.has_prefix("--allow-run") {
      let command = parse_flag_value(arg, "--allow-run")
      permissions.allow(PermissionDescriptor::Run(command~))
      i += 1
      continue
    }

    // Parse --deny-* flags
    if arg.has_prefix("--deny-read") {
      let path = parse_flag_value(arg, "--deny-read")
      permissions.deny(PermissionDescriptor::Read(path~))
      i += 1
      continue
    }

    if arg.has_prefix("--deny-write") {
      let path = parse_flag_value(arg, "--deny-write")
      permissions.deny(PermissionDescriptor::Write(path~))
      i += 1
      continue
    }

    if arg.has_prefix("--deny-net") {
      let host = parse_flag_value(arg, "--deny-net")
      permissions.deny(PermissionDescriptor::Net(host~))
      i += 1
      continue
    }

    if arg.has_prefix("--deny-env") {
      let variable = parse_flag_value(arg, "--deny-env")
      permissions.deny(PermissionDescriptor::Env(variable~))
      i += 1
      continue
    }

    if arg.has_prefix("--deny-run") {
      let command = parse_flag_value(arg, "--deny-run")
      permissions.deny(PermissionDescriptor::Run(command~))
      i += 1
      continue
    }

    // Unknown flag or program arg
    program_args.push(arg)
    i += 1
  }

  { permissions, program_args }
}

/// Parse flag value from --flag=value or --flag (returns None)
fn parse_flag_value(arg : String, prefix : String) -> String? {
  if arg == prefix {
    return None
  }
  let prefix_eq = prefix + "="
  if arg.has_prefix(prefix_eq) {
    let value = arg.substring(start=prefix_eq.length())
    if value.is_empty() {
      return None
    }
    return Some(value)
  }
  None
}

/// Create SandboxedBackend from CLI args
pub fn create_sandbox_from_args(args : Array[String]) -> (SandboxedBackend, Array[String]) {
  let parsed = parse_args(args)
  let backend = SandboxedBackend::new(parsed.permissions)
  (backend, parsed.program_args)
}
