///|
async test "HTTP transport preserves protocol headers and binary bodies" {
  @async.with_timeout(5000, () => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let requests : Array[(String, String?, String?, Bytes)] = []
    let response_body = b"\x00PACK\x80\xFF"
    @async.with_task_group() <| group => {
      group.spawn_bg(no_wait=true) <| () => {
        server.run_forever() <| (request, body, connection) => {
          requests.push((
            request.path,
            request.headers.get("git-protocol"),
            request.headers.get("content-type"),
            body.read_all().binary(),
          ))
          connection.send_response(200, "OK")
          connection.write(response_body)
          connection.end_response()
        }
      }
      let remote = "http://\{server.addr}/repo.git"
      assert_eq(@git.upload_pack_info_refs_http(remote, true), response_body)
      let request_body = b"\x00want\xFF"
      assert_eq(
        @git.upload_pack_request_http(remote, request_body, true),
        response_body,
      )
      assert_eq(requests.length(), 2)
      assert_eq(requests[0], (
        "/repo/info/refs?service=git-upload-pack", Some("version=2"), None, b"",
      ))
      assert_eq(requests[1], (
        "/repo/git-upload-pack", Some("version=2"),
        Some("application/x-git-upload-pack-request"), request_body,
      ))
    }
  })
}

///|
async test "HTTP transport preserves non-success errors" {
  @async.with_timeout(5000, () => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    @async.with_task_group() <| group => {
      group.spawn_bg(no_wait=true) <| () => {
        server.run_forever() <| (_request, _body, connection) => {
          connection.send_response(403, "Forbidden")
          connection.end_response()
        }
      }
      let remote = "http://\{server.addr}/repo.git"
      try @git.upload_pack_info_refs_http(remote, false) catch {
        @git.GitError::ProtocolError(message) =>
          assert_eq(message, "Failed to fetch info/refs: HTTP 403")
        error => fail("Unexpected error: \{error}")
      } noraise {
        _ => fail("Expected HTTP 403 to be rejected")
      }
      try @git.upload_pack_request_http(remote, b"", false) catch {
        @git.GitError::ProtocolError(message) =>
          assert_eq(message, "Failed to upload-pack: HTTP 403")
        error => fail("Unexpected error: \{error}")
      } noraise {
        _ => fail("Expected HTTP 403 to be rejected")
      }
    }
  })
}
