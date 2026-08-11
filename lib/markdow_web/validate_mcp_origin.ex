defmodule MarkdowWeb.ValidateMcpOrigin do
  @moduledoc false

  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(options), do: options

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, options) do
    case get_req_header(conn, "origin") do
      [] -> conn
      [origin] -> validate(conn, origin, options)
      _origins -> forbidden(conn)
    end
  end

  defp validate(conn, origin, options) do
    allowed_origins =
      conn.private[:markdow_allowed_mcp_origins] ||
        Keyword.get(options, :allowed_origins) ||
        Application.fetch_env!(:markdow, :allowed_mcp_origins)

    if origin in allowed_origins, do: conn, else: forbidden(conn)
  end

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      403,
      JSON.encode!(%{
        jsonrpc: "2.0",
        error: %{code: -32_000, message: "Origin is not allowed"}
      })
    )
    |> halt()
  end
end
