defmodule Markdow.MCP do
  @moduledoc "A streamable Hypertext Transfer Protocol server for Model Context Protocol clients."

  @behaviour Plug

  import Plug.Conn

  alias Markdow.Index
  alias Markdow.Operations

  @protocol_version "2025-06-18"
  @supported_protocol_versions ["2025-06-18", "2025-03-26"]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case requested_protocol_version(conn) do
      {:ok, _version} -> dispatch_method(conn)
      {:error, version} -> unsupported_protocol_version(conn, version)
    end
  end

  defp dispatch_method(%{method: "POST"} = conn), do: dispatch(conn, conn.body_params)

  defp dispatch_method(%{method: "DELETE"} = conn), do: send_resp(conn, 204, "")

  defp dispatch_method(conn) do
    conn
    |> put_resp_header("allow", "POST, DELETE")
    |> send_resp(405, "")
  end

  defp dispatch(conn, %{"method" => "initialize", "id" => id} = request) do
    requested_version = get_in(request, ["params", "protocolVersion"])

    version =
      if requested_version in @supported_protocol_versions,
        do: requested_version,
        else: @protocol_version

    conn
    |> put_resp_header("mcp-session-id", session_id())
    |> result(id, %{
      protocolVersion: version,
      capabilities: %{tools: %{listChanged: false}},
      serverInfo: %{name: "markdow", title: "Markdow notes", version: "0.1.0"},
      instructions:
        "Select and inspect the intended vault before changing it. Preserve Markdown, frontmatter, and wikilinks. Never delete a note or rebuild a vault index unless the user explicitly asks."
    })
  end

  defp dispatch(conn, %{"method" => "tools/list", "id" => id}) do
    tools =
      Enum.map(Operations.all(), &Map.take(&1, [:name, :description, :inputSchema, :annotations]))

    result(conn, id, %{tools: tools})
  end

  defp dispatch(
         conn,
         %{"method" => "tools/call", "id" => id, "params" => %{"name" => name} = params}
       ) do
    with {:ok, operation} <- Operations.fetch(name),
         :ok <- authorize_operation(conn, operation),
         {:ok, value} <-
           Operations.call(
             name,
             Map.get(params, "arguments", %{}),
             index(conn),
             conn.assigns.authorization
           ) do
      result(conn, id, %{
        content: [%{type: "text", text: JSON.encode!(value)}],
        structuredContent: %{result: value}
      })
    else
      :error -> tool_error(conn, id, :unknown_operation)
      {:error, reason} -> tool_error(conn, id, reason)
    end
  end

  defp dispatch(conn, %{"method" => "notifications/" <> _notification}),
    do: send_resp(conn, 202, "")

  defp dispatch(conn, %{"id" => id}), do: error(conn, id, -32_601, "Method not found")

  defp dispatch(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(400, JSON.encode!(%{error: "invalid_request"}))
  end

  defp authorize_operation(_conn, %{scope: nil}), do: :ok

  defp authorize_operation(conn, %{scope: required_scope}) do
    granted =
      case conn.assigns.authorization.scopes do
        scopes when is_binary(scopes) -> String.split(scopes)
        scopes when is_list(scopes) -> scopes
      end

    if required_scope in granted,
      do: :ok,
      else: {:error, :insufficient_scope}
  end

  defp tool_error(conn, id, reason) do
    result(conn, id, %{
      content: [%{type: "text", text: error_text(reason)}],
      isError: true
    })
  end

  defp error_text(%Ecto.Changeset{}), do: "invalid_arguments"
  defp error_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(_reason), do: "operation_failed"

  defp result(conn, id, value), do: respond(conn, %{jsonrpc: "2.0", id: id, result: value})

  defp error(conn, id, code, message),
    do: respond(conn, %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}})

  defp respond(conn, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, JSON.encode!(body))
  end

  defp requested_protocol_version(conn) do
    case get_req_header(conn, "mcp-protocol-version") do
      [] -> {:ok, nil}
      [version] when version in @supported_protocol_versions -> {:ok, version}
      [version] -> {:error, version}
      _versions -> {:error, "multiple values"}
    end
  end

  defp unsupported_protocol_version(conn, version) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      400,
      JSON.encode!(%{
        jsonrpc: "2.0",
        id: nil,
        error: %{
          code: -32_600,
          message:
            "Unsupported Model Context Protocol version #{version}. Supported versions: #{Enum.join(@supported_protocol_versions, ", ")}."
        }
      })
    )
  end

  defp index(conn), do: conn.private[:markdow_index] || Index.context()

  defp session_id,
    do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
end
