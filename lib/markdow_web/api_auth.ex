defmodule MarkdowWeb.ApiAuth do
  @moduledoc "Authenticates application keys and auth.md bearer access tokens."

  import Plug.Conn

  alias Markdow.AgentAuth
  alias Markdow.Index
  alias Markdow.OAuth
  alias MarkdowWeb.PublicOrigin

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    required_scopes = Keyword.get(opts, :scopes, [])

    with {:ok, token} <- credential(conn),
         {:ok, authorization} <- authorize(conn, token, required_scopes) do
      assign(conn, :authorization, authorization)
    else
      {:error, :insufficient_scope} -> unauthorized(conn, "insufficient_scope", required_scopes)
      _error -> unauthorized(conn, "invalid_token", required_scopes)
    end
  end

  # Two kinds of credential reach the same operations. A claim ceremony token is
  # tried first because it is the one Markdow issues most and the one bound to a
  # resource, and a registered client's token is tried second. Both resolve to
  # the same authorization shape, so nothing downstream branches on which was
  # presented.
  #
  # `:insufficient_scope` from the first path is returned rather than retried:
  # the token was recognised and simply did not carry the scope, and turning
  # that into an `invalid_token` by falling through would tell the caller to go
  # and get a different credential when the one they hold is the right one.
  defp authorize(conn, token, required_scopes) do
    case AgentAuth.authorize(token, required_scopes,
           index: conn.private[:markdow_index] || Index.context(),
           issuer: PublicOrigin.from_conn(conn),
           api_key: conn.private[:markdow_api_key] || Application.get_env(:markdow, :api_key),
           resource: requested_resource(conn)
         ) do
      {:ok, authorization} -> {:ok, authorization}
      {:error, :insufficient_scope} -> {:error, :insufficient_scope}
      {:error, _reason} -> OAuth.authorize(token, required_scopes)
    end
  end

  defp requested_resource(conn) do
    if String.starts_with?(conn.request_path, "/mcp"),
      do: PublicOrigin.from_conn(conn) <> "/mcp",
      else: PublicOrigin.from_conn(conn)
  end

  defp credential(conn) do
    case {get_req_header(conn, "authorization"), get_req_header(conn, "x-api-key")} do
      {["Bearer " <> token], _api_key} when byte_size(token) > 0 -> {:ok, token}
      {_authorization, [api_key]} when byte_size(api_key) > 0 -> {:ok, api_key}
      _headers -> {:error, :missing_token}
    end
  end

  defp unauthorized(conn, error, scopes) do
    metadata_path =
      if String.starts_with?(conn.request_path, "/mcp"),
        do: "/.well-known/oauth-protected-resource/mcp",
        else: "/.well-known/oauth-protected-resource"

    metadata = PublicOrigin.from_conn(conn) <> metadata_path

    conn
    |> put_resp_header(
      "www-authenticate",
      ~s(Bearer resource_metadata="#{metadata}", error="#{error}", scope="#{Enum.join(scopes, " ")}")
    )
    |> put_resp_content_type("application/json")
    |> send_resp(401, JSON.encode!(%{error: error}))
    |> halt()
  end
end
