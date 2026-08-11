defmodule MarkdowWeb.McpTest do
  use Markdow.DataCase, async: true

  alias Markdow.DataCase
  alias Markdow.Embeddings.OpenAI
  alias Markdow.Operations

  setup :verify_on_exit!

  test "requires a bearer credential with discovery metadata", %{index: index} do
    origin = DataCase.public_origin()
    response = mcp(index, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}, nil)

    assert response.status == 401

    assert Plug.Conn.get_resp_header(response, "www-authenticate") == [
             ~s(Bearer resource_metadata="#{origin}/.well-known/oauth-protected-resource/mcp", error="invalid_token", scope="mcp")
           ]
  end

  test "negotiates a protocol session and exposes the shared operations", %{index: index} do
    initialized =
      mcp(index, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{"protocolVersion" => "2025-06-18"}
      })

    assert initialized.status == 200
    assert Plug.Conn.get_resp_header(initialized, "mcp-session-id") != []
    assert json_response(initialized)["result"]["protocolVersion"] == "2025-06-18"

    tools =
      index
      |> mcp(%{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"})
      |> json_response()
      |> get_in(["result", "tools"])

    assert Enum.map(tools, & &1["name"]) == Operations.names()
    assert Enum.all?(tools, &is_map(&1["inputSchema"]))
  end

  test "manages a linked vault through tools", %{index: index} do
    assert %{"id" => "mcp-user"} =
             call_tool(index, 1, "create_user", %{
               "id" => "mcp-user",
               "email" => "mcp@example.com",
               "name" => "Model Context Protocol user"
             })

    assert %{"id" => "mcp-vault", "user_id" => "mcp-user"} =
             call_tool(index, 2, "create_vault", %{
               "id" => "mcp-vault",
               "user_id" => "mcp-user",
               "name" => "Model Context Protocol vault"
             })

    assert %{"id" => "architecture"} =
             call_tool(index, 3, "create_note", %{
               "vault_id" => "mcp-vault",
               "id" => "architecture",
               "body" => "# Architecture\n\nPostgreSQL powers search."
             })

    assert %{"id" => "plan"} =
             call_tool(index, 4, "create_note", %{
               "vault_id" => "mcp-vault",
               "id" => "plan",
               "body" => "# Plan\n\nReview [[Architecture]]."
             })

    assert [%{"id" => "architecture"}] =
             call_tool(index, 5, "search_notes", %{
               "vault_id" => "mcp-vault",
               "q" => "powers"
             })

    assert [%{"id" => "plan", "context" => context}] =
             call_tool(index, 6, "list_backlinks", %{
               "vault_id" => "mcp-vault",
               "id" => "architecture"
             })

    assert context == "Review [[Architecture]]."

    graph =
      call_tool(index, 7, "get_note_graph", %{
        "vault_id" => "mcp-vault",
        "id" => "plan",
        "depth" => 2
      })

    assert Enum.map(graph["nodes"], & &1["id"]) == ["plan", "architecture"]

    assert %{"id" => "plan", "title" => "Updated"} =
             call_tool(index, 8, "update_note", %{
               "vault_id" => "mcp-vault",
               "id" => "plan",
               "body" => "# Updated\n\nDone."
             })

    assert %{"id" => "plan", "deleted" => true} =
             call_tool(index, 9, "delete_note", %{
               "vault_id" => "mcp-vault",
               "id" => "plan"
             })

    attachment = <<0, 1, 255, 10>>

    assert %{"path" => "Assets/diagram.bin", "kind" => "asset"} =
             call_tool(index, 10, "write_document", %{
               "vault_id" => "mcp-vault",
               "path" => "Assets/diagram.bin",
               "data_base64" => Base.encode64(attachment)
             })

    assert %{"data_base64" => encoded_attachment} =
             call_tool(index, 11, "read_document", %{
               "vault_id" => "mcp-vault",
               "path" => "Assets/diagram.bin"
             })

    assert Base.decode64!(encoded_attachment) == attachment
  end

  test "accepts only configured browser origins", %{index: index} do
    allowed =
      :post
      |> Plug.Test.conn(
        "/mcp",
        JSON.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
      )
      |> Plug.Conn.put_private(:markdow_index, index)
      |> Plug.Conn.put_private(:markdow_api_key, "test")
      |> Plug.Conn.put_private(:markdow_allowed_mcp_origins, ["https://notes.example"])
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("authorization", "Bearer test")
      |> Plug.Conn.put_req_header("origin", "https://notes.example")
      |> MarkdowWeb.Endpoint.call([])

    assert allowed.status == 200

    rejected =
      :post
      |> Plug.Test.conn(
        "/mcp",
        JSON.encode!(%{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"})
      )
      |> Plug.Conn.put_private(:markdow_index, index)
      |> Plug.Conn.put_private(:markdow_api_key, "test")
      |> Plug.Conn.put_private(:markdow_allowed_mcp_origins, ["https://notes.example"])
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("authorization", "Bearer test")
      |> Plug.Conn.put_req_header("origin", "https://attacker.example")
      |> MarkdowWeb.Endpoint.call([])

    assert json_response(rejected, 403)["error"]["message"] == "Origin is not allowed"
  end

  test "rejects ambiguous origins and supports explicit and runtime allowlists" do
    origin = DataCase.public_origin()

    runtime_allowed =
      :get
      |> Plug.Test.conn("/mcp")
      |> Plug.Conn.put_req_header("origin", origin)
      |> MarkdowWeb.ValidateMcpOrigin.call([])

    refute runtime_allowed.halted

    explicitly_allowed =
      :get
      |> Plug.Test.conn("/mcp")
      |> Plug.Conn.put_req_header("origin", "https://notes.example")
      |> MarkdowWeb.ValidateMcpOrigin.call(allowed_origins: ["https://notes.example"])

    refute explicitly_allowed.halted

    ambiguous =
      :get
      |> Plug.Test.conn("/mcp")
      |> Map.update!(:req_headers, fn headers ->
        [{"origin", "https://first.example"}, {"origin", "https://second.example"} | headers]
      end)
      |> MarkdowWeb.ValidateMcpOrigin.call(allowed_origins: ["https://first.example"])

    assert ambiguous.halted
    assert ambiguous.status == 403
    assert JSON.decode!(ambiguous.resp_body)["error"]["message"] == "Origin is not allowed"
  end

  test "rejects unsupported protocol versions", %{index: index} do
    response =
      :post
      |> Plug.Test.conn(
        "/mcp",
        JSON.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
      )
      |> Plug.Conn.put_private(:markdow_index, index)
      |> Plug.Conn.put_private(:markdow_api_key, "test")
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("authorization", "Bearer test")
      |> Plug.Conn.put_req_header("mcp-protocol-version", "1900-01-01")
      |> MarkdowWeb.Endpoint.call([])

    assert response.status == 400
    assert json_response(response, 400)["error"]["code"] == -32_600
  end

  test "configures and validates a bring-your-own embedding credential through tools", %{
    index: index
  } do
    configured =
      call_tool(index, 1, "configure_embedding", %{
        "vault_id" => "default",
        "model" => "text-embedding-3-small",
        "dimensions" => 2,
        "token" => "mcp-provider-token"
      })

    assert configured["credential_hint"] == "••••oken"
    refute JSON.encode!(configured) =~ "mcp-provider-token"

    expect(OpenAI, :embed, fn _configuration, "mcp-provider-token", input ->
      assert input =~ "Validate"

      {:ok,
       %{
         embedding: [0.1, 0.2],
         model: "text-embedding-3-small",
         usage: %{"total_tokens" => 5}
       }}
    end)

    assert %{"status" => "valid", "dimensions" => 2} =
             call_tool(index, 2, "validate_embedding_configuration", %{
               "vault_id" => "default"
             })
  end

  test "handles lifecycle requests, notifications, and protocol errors", %{index: index} do
    health = call_tool(index, 1, "health", %{})
    assert health == %{"status" => "ok"}

    unknown_tool =
      index
      |> mcp(%{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/call",
        "params" => %{"name" => "unknown", "arguments" => %{}}
      })
      |> json_response()

    assert unknown_tool["result"]["isError"]

    assert unknown_tool["result"]["content"] == [
             %{"type" => "text", "text" => "unknown_operation"}
           ]

    invalid_arguments =
      index
      |> mcp(%{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => %{"name" => "get_note", "arguments" => %{}}
      })
      |> json_response()

    assert invalid_arguments["result"]["isError"]

    method_error =
      index
      |> mcp(%{"jsonrpc" => "2.0", "id" => 4, "method" => "prompts/list"})
      |> json_response()

    assert method_error["error"]["code"] == -32_601

    notification = mcp(index, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})
    assert notification.status == 202

    malformed = mcp(index, %{})
    assert malformed.status == 400

    deleted = DataCase.endpoint_conn(:delete, "/mcp", nil, index, "test")
    assert deleted.status == 204

    not_allowed = DataCase.endpoint_conn(:get, "/mcp", nil, index, "test")
    assert not_allowed.status == 405
    assert Plug.Conn.get_resp_header(not_allowed, "allow") == ["POST, DELETE"]

    event_stream_probe =
      :get
      |> Plug.Test.conn("/mcp")
      |> Plug.Conn.put_private(:markdow_index, index)
      |> Plug.Conn.put_private(:markdow_api_key, "test")
      |> Plug.Conn.put_req_header("accept", "text/event-stream")
      |> Plug.Conn.put_req_header("authorization", "Bearer test")
      |> MarkdowWeb.Endpoint.call([])

    assert event_stream_probe.status == 405
    assert Plug.Conn.get_resp_header(event_stream_probe, "allow") == ["POST, DELETE"]
  end

  defp call_tool(index, id, name, arguments) do
    response =
      mcp(index, %{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => "tools/call",
        "params" => %{"name" => name, "arguments" => arguments}
      })
      |> json_response()

    assert response["result"]["isError"] != true
    response["result"]["structuredContent"]["result"]
  end

  defp mcp(index, body, authorization \\ "test") do
    DataCase.endpoint_conn(:post, "/mcp", body, index, authorization)
  end

  defp json_response(conn, status \\ 200) do
    assert conn.status == status
    JSON.decode!(conn.resp_body)
  end
end
