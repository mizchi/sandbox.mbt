/// Core agent implementation

///|
/// LLM client interface
/// Implementations should handle API communication
pub(open) trait LLMClient {
  /// Send messages to the LLM and get a response
  chat(Self, Array[Message], Array[ToolDef]) -> Message raise Error
}

///|
/// The coding agent
pub(all) struct Agent {
  config : AgentConfig
  executor : ToolExecutor
  messages : Array[Message]
  tools : Array[ToolDef]
}

///|
/// Create a new agent with default config
pub fn Agent::new(shell : @shell.Shell, ctx : @posix.PosixContext) -> Agent {
  Agent::new_with_config(shell, ctx, AgentConfig::default())
}

///|
/// Create a new agent with custom config
pub fn Agent::new_with_config(
  shell : @shell.Shell,
  ctx : @posix.PosixContext,
  config : AgentConfig,
) -> Agent {
  let executor = ToolExecutor::new(shell, ctx)
  let tools = get_builtin_tools()
  let messages = [Message::system(config.system_prompt)]
  { config, executor, messages, tools }
}

///|
/// Add a user message
pub fn Agent::add_user_message(self : Agent, content : String) -> Unit {
  self.messages.push(Message::user(content))
}

///|
/// Add an assistant message
pub fn Agent::add_assistant_message(
  self : Agent,
  content : String,
  tool_calls : Array[ToolCall],
) -> Unit {
  self.messages.push(Message::assistant(content, tool_calls))
}

///|
/// Process tool calls and add results to messages
pub fn Agent::process_tool_calls(
  self : Agent,
  tool_calls : Array[ToolCall],
) -> Array[ToolResult] {
  let results : Array[ToolResult] = []
  for call in tool_calls {
    let result = self.executor.execute(call)
    results.push(result)
    // Add tool result message
    let content = if result.success {
      result.output
    } else {
      "Error: " + result.error.unwrap_or("Unknown error") + "\n" + result.output
    }
    self.messages.push(Message::tool_result(call.id, content))
  }
  results
}

///|
/// Run a single turn with the LLM
/// Returns (response_content, has_tool_calls)
pub fn[C : LLMClient] Agent::run_turn(
  self : Agent,
  client : C,
) -> (String, Bool) raise Error {
  let response = client.chat(self.messages, self.tools)
  self.messages.push(response)
  if response.tool_calls.length() > 0 {
    ignore(self.process_tool_calls(response.tool_calls))
    (response.content, true)
  } else {
    (response.content, false)
  }
}

///|
/// Run the agent loop until completion or max turns
pub fn[C : LLMClient] Agent::run(
  self : Agent,
  client : C,
  user_input : String,
) -> String raise Error {
  self.add_user_message(user_input)
  for turns = 0; turns < self.config.max_turns; turns = turns + 1 {
    let (content, has_tool_calls) = self.run_turn(client)
    if not(has_tool_calls) {
      return content
    }
  }
  // Max turns reached
  "Max turns (" + self.config.max_turns.to_string() + ") reached"
}

///|
/// Get current message history
pub fn Agent::get_messages(self : Agent) -> Array[Message] {
  self.messages
}

///|
/// Clear message history (keeps system prompt)
pub fn Agent::clear_history(self : Agent) -> Unit {
  let system = self.messages[0]
  self.messages.clear()
  self.messages.push(system)
}

///|
/// AgentRunner for manual step-by-step execution
pub(all) struct AgentRunner {
  agent : Agent
  pending_tool_calls : Array[ToolCall]
}

///|
/// Create a new agent runner
pub fn AgentRunner::new(agent : Agent) -> AgentRunner {
  { agent, pending_tool_calls: [] }
}

///|
/// Set user input
pub fn AgentRunner::set_user_input(self : AgentRunner, input : String) -> Unit {
  self.agent.add_user_message(input)
}

///|
/// Process LLM response (call this after getting response from LLM)
pub fn AgentRunner::process_response(
  self : AgentRunner,
  content : String,
  tool_calls : Array[ToolCall],
) -> Unit {
  self.agent.add_assistant_message(content, tool_calls)
  self.pending_tool_calls.clear()
  for call in tool_calls {
    self.pending_tool_calls.push(call)
  }
}

///|
/// Check if there are pending tool calls
pub fn AgentRunner::has_pending_tools(self : AgentRunner) -> Bool {
  self.pending_tool_calls.length() > 0
}

///|
/// Execute pending tool calls
pub fn AgentRunner::execute_tools(self : AgentRunner) -> Array[ToolResult] {
  let calls = self.pending_tool_calls.copy()
  self.pending_tool_calls.clear()
  self.agent.process_tool_calls(calls)
}

///|
/// Get messages for LLM request
pub fn AgentRunner::get_messages(self : AgentRunner) -> Array[Message] {
  self.agent.messages
}

///|
/// Get tool definitions
pub fn AgentRunner::get_tools(self : AgentRunner) -> Array[ToolDef] {
  self.agent.tools
}

///|
/// Check if agent should continue (within max turns and has pending work)
pub fn AgentRunner::should_continue(self : AgentRunner, turns : Int) -> Bool {
  turns < self.agent.config.max_turns && self.has_pending_tools()
}
