/// Agent types for LLM-based coding agent

/// Role of a message
pub(all) enum Role {
  System
  User
  Assistant
  Tool
}

/// Convert role to string
pub fn Role::to_string(self : Role) -> String {
  match self {
    System => "system"
    User => "user"
    Assistant => "assistant"
    Tool => "tool"
  }
}

/// Parse role from string
pub fn Role::from_string(s : String) -> Role? {
  match s {
    "system" => Some(System)
    "user" => Some(User)
    "assistant" => Some(Assistant)
    "tool" => Some(Tool)
    _ => None
  }
}

/// A chat message
pub(all) struct Message {
  role : Role
  content : String
  tool_calls : Array[ToolCall]
  tool_call_id : String?
}

/// Create a new message
pub fn Message::new(
  role : Role,
  content : String,
  tool_calls : Array[ToolCall],
  tool_call_id : String?
) -> Message {
  { role, content, tool_calls, tool_call_id }
}

/// Create a system message
pub fn Message::system(content : String) -> Message {
  Message::new(System, content, [], None)
}

/// Create a user message
pub fn Message::user(content : String) -> Message {
  Message::new(User, content, [], None)
}

/// Create an assistant message
pub fn Message::assistant(content : String, tool_calls : Array[ToolCall]) -> Message {
  Message::new(Assistant, content, tool_calls, None)
}

/// Create a tool result message
pub fn Message::tool_result(tool_call_id : String, content : String) -> Message {
  Message::new(Tool, content, [], Some(tool_call_id))
}

/// A tool call from the LLM
pub(all) struct ToolCall {
  id : String
  name : String
  arguments : String // JSON string
}

/// Create a new tool call
pub fn ToolCall::new(id : String, name : String, arguments : String) -> ToolCall {
  { id, name, arguments }
}

/// Tool definition
pub(all) struct ToolDef {
  name : String
  description : String
  parameters_schema : String // JSON schema
}

/// Create a new tool definition
pub fn ToolDef::new(
  name : String,
  description : String,
  parameters_schema : String
) -> ToolDef {
  { name, description, parameters_schema }
}

/// Result of executing a tool
pub(all) struct ToolResult {
  success : Bool
  output : String
  error : String?
}

/// Create a successful tool result
pub fn ToolResult::ok(output : String) -> ToolResult {
  { success: true, output, error: None }
}

/// Create a failed tool result
pub fn ToolResult::err(error : String) -> ToolResult {
  { success: false, output: "", error: Some(error) }
}

/// Agent configuration
pub(all) struct AgentConfig {
  model : String
  max_turns : Int
  system_prompt : String
}

/// Default agent configuration
pub fn AgentConfig::default() -> AgentConfig {
  {
    model: "claude-sonnet-4-20250514",
    max_turns: 10,
    system_prompt: "You are a coding assistant with access to a shell environment.",
  }
}
