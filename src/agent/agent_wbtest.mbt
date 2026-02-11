/// Tests for the agent module

///|
/// Mock LLM client for testing
struct MockLLMClient {
  responses : Array[Message]
  mut call_count : Int
}

///|
fn MockLLMClient::new(responses : Array[Message]) -> MockLLMClient {
  { responses, call_count: 0 }
}

///|
suberror MockError {
  NoMoreResponses
}

///|
impl LLMClient for MockLLMClient with chat(self, _messages, _tools) {
  if self.call_count < self.responses.length() {
    let response = self.responses[self.call_count]
    self.call_count = self.call_count + 1
    response
  } else {
    raise MockError::NoMoreResponses
  }
}

///|
test "parse_json_string extracts values" {
  let json = "{\"command\":\"echo hello\",\"path\":\"/tmp\"}"
  assert_eq(parse_json_string(json, "command"), Some("echo hello"))
  assert_eq(parse_json_string(json, "path"), Some("/tmp"))
  assert_eq(parse_json_string(json, "missing"), None)
}

///|
test "parse_json_string handles escapes" {
  let json = "{\"content\":\"line1\\nline2\"}"
  assert_eq(parse_json_string(json, "content"), Some("line1\nline2"))
}

///|
test "ToolExecutor executes bash command" {
  let ctx = @posix.PosixContext::default()
  let shell = @shell.Shell::new(ctx)
  let executor = ToolExecutor::new(shell, ctx)
  let call = ToolCall::new("1", "bash", "{\"command\":\"echo hello\"}")
  let result = executor.execute(call)
  assert_true(result.success)
  assert_eq(result.output.trim(), "hello")
}

///|
test "ToolExecutor executes write and read file" {
  let ctx = @posix.PosixContext::default()
  let shell = @shell.Shell::new(ctx)
  let executor = ToolExecutor::new(shell, ctx)

  // Write file
  let write_call = ToolCall::new(
    "1", "write_file", "{\"path\":\"/test.txt\",\"content\":\"hello world\"}",
  )
  let write_result = executor.execute(write_call)
  assert_true(write_result.success)

  // Read file
  let read_call = ToolCall::new("2", "read_file", "{\"path\":\"/test.txt\"}")
  let read_result = executor.execute(read_call)
  assert_true(read_result.success)
  assert_eq(read_result.output.trim(), "hello world")
}

///|
test "ToolExecutor executes list_files" {
  let ctx = @posix.PosixContext::default()
  let shell = @shell.Shell::new(ctx)
  let executor = ToolExecutor::new(shell, ctx)

  // Create directory and file
  ignore(shell.exec_line("mkdir /mydir"))
  ignore(shell.exec_line("touch /mydir/file1.txt"))

  let call = ToolCall::new("1", "list_files", "{\"path\":\"/mydir\"}")
  let result = executor.execute(call)
  assert_true(result.success)
  assert_true(result.output.contains("file1.txt"))
}

///|
test "Agent processes tool calls" {
  let ctx = @posix.PosixContext::default()
  let shell = @shell.Shell::new(ctx)
  let agent = Agent::new(shell, ctx)

  // Simulate tool calls
  let tool_calls = [
    ToolCall::new("tc1", "bash", "{\"command\":\"echo test1\"}"),
    ToolCall::new("tc2", "bash", "{\"command\":\"echo test2\"}"),
  ]
  let results = agent.process_tool_calls(tool_calls)
  assert_eq(results.length(), 2)
  assert_true(results[0].success)
  assert_true(results[1].success)

  // Check messages were added
  let messages = agent.get_messages()
  // System + 2 tool results
  assert_eq(messages.length(), 3)
}

///|
test "Agent run with mock client" {
  let ctx = @posix.PosixContext::default()
  let shell = @shell.Shell::new(ctx)
  let agent = Agent::new(shell, ctx)

  // Mock client that first returns a tool call, then a final response
  let client = MockLLMClient::new([
    Message::assistant("Let me check the directory.", [
      ToolCall::new("tc1", "bash", "{\"command\":\"pwd\"}"),
    ]),
    Message::assistant("The current directory is /.", []),
  ])
  let result = agent.run(client, "What is the current directory?")
  assert_eq(result, "The current directory is /.")
  assert_eq(client.call_count, 2)
}

///|
test "AgentRunner step-by-step execution" {
  let ctx = @posix.PosixContext::default()
  let shell = @shell.Shell::new(ctx)
  let agent = Agent::new(shell, ctx)
  let runner = AgentRunner::new(agent)

  // Set user input
  runner.set_user_input("Create a file")
  assert_false(runner.has_pending_tools())

  // Process LLM response with tool call
  runner.process_response("I'll create a file.", [
    ToolCall::new(
      "tc1", "write_file", "{\"path\":\"/hello.txt\",\"content\":\"Hello!\"}",
    ),
  ])
  assert_true(runner.has_pending_tools())

  // Execute tools
  let results = runner.execute_tools()
  assert_eq(results.length(), 1)
  assert_true(results[0].success)
  assert_false(runner.has_pending_tools())

  // Verify file was created
  let read_result = shell.exec_line("cat /hello.txt")
  assert_eq(read_result.stdout.trim(), "Hello!")
}

///|
test "get_builtin_tools returns expected tools" {
  let tools = get_builtin_tools()
  assert_eq(tools.length(), 4)

  let names = tools.map(fn(t) { t.name })
  assert_true(names.contains("bash"))
  assert_true(names.contains("read_file"))
  assert_true(names.contains("write_file"))
  assert_true(names.contains("list_files"))
}
