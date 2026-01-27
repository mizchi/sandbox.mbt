/// Agent CLI Demo
/// Demonstrates how the agent works with mock LLM responses

///|
fn main {
  println("MoonBit Coding Agent Demo")
  println("=========================")
  println("")

  // Create the sandbox environment
  let ctx = @posix.PosixContext::default()
  let shell = @shell.Shell::new(ctx)
  let agent = @agent.Agent::new(shell, ctx)
  let runner = @agent.AgentRunner::new(agent)

  // Simulate a user request
  let user_request = "Create a hello world program"
  println("User: " + user_request)
  println("")

  runner.set_user_input(user_request)

  // Simulate LLM response with tool calls
  println("Assistant: I'll create a hello world program for you.")
  println("")

  // First tool call: create a file
  let tool_calls = [
    @agent.ToolCall::new(
      "tc1",
      "write_file",
      "{\"path\":\"/hello.mbt\",\"content\":\"fn main { println(\\\"Hello, World!\\\") }\"}",
    ),
  ]
  runner.process_response("I'll create a hello world program for you.", tool_calls)

  // Execute the tool calls
  println("Executing tools...")
  let results = runner.execute_tools()
  for i, result in results {
    println("Tool " + (i + 1).to_string() + ": " + (if result.success { "OK" } else { "FAILED" }))
    if result.output.length() > 0 {
      println("  Output: " + result.output)
    }
  }
  println("")

  // Second tool call: verify the file
  let verify_calls = [
    @agent.ToolCall::new("tc2", "read_file", "{\"path\":\"/hello.mbt\"}"),
  ]
  runner.process_response("Let me verify the file was created.", verify_calls)

  println("Verifying file...")
  let verify_results = runner.execute_tools()
  for result in verify_results {
    if result.success {
      println("File contents:")
      println("  " + result.output)
    }
  }
  println("")

  // Final response
  runner.process_response(
    "I've created hello.mbt with a simple hello world program.",
    [],
  )

  println("Assistant: I've created hello.mbt with a simple hello world program.")
  println("")
  println("Demo complete!")
}
