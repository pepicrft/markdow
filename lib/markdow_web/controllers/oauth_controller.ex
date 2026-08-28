defmodule MarkdowWeb.OAuthController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  @behaviour Boruta.Oauth.TokenApplication

  alias Markdow.AgentAuth
  alias Markdow.Index
  alias Markdow.OAuth
  alias MarkdowWeb.PublicOrigin
  alias OpenApiSpex.Schema

  @claim_grant AgentAuth.claim_grant()
  @jwt_bearer_grant AgentAuth.jwt_bearer_grant()

  tags ["Agent authentication"]
  security []

  operation :token,
    operation_id: "exchange_agent_credential",
    summary: "Poll a claim or exchange a service identity assertion",
    request_body:
      {"Token grant", "application/x-www-form-urlencoded",
       %Schema{type: :object, additionalProperties: true}},
    responses: [ok: {"Access token", "application/json", %Schema{type: :object}}]

  operation :revoke,
    operation_id: "revoke_agent_credential",
    summary: "Revoke one agent access token",
    request_body:
      {"Revocation request", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{
           token: %Schema{type: :string},
           token_type_hint: %Schema{type: :string}
         }
       }},
    responses: [ok: {"Credential revoked", "text/plain", %Schema{type: :string}}]

  def token(conn, %{"grant_type" => grant, "claim_token" => claim_token})
      when grant == @claim_grant do
    token_response(conn, AgentAuth.exchange_claim(claim_token, auth_opts(conn)))
  end

  def token(conn, %{"grant_type" => grant, "assertion" => assertion} = params)
      when grant == @jwt_bearer_grant do
    token_response(
      conn,
      AgentAuth.exchange_assertion(assertion, params["resource"], auth_opts(conn))
    )
  end

  def token(conn, _params), do: Boruta.Oauth.token(conn, __MODULE__)

  # RFC 7009 revocation is idempotent and does not tell the caller whether the
  # token existed. Both kinds are attempted because the endpoint is advertised
  # for the whole authorization server, and a caller holding a registered
  # client's token has no other way to hand it back.
  def revoke(conn, %{"token" => token}) do
    AgentAuth.revoke_access_token(token, auth_opts(conn))
    OAuth.revoke_token(token)

    send_resp(conn, 200, "")
  end

  def revoke(conn, _params), do: send_resp(conn, 200, "")

  @impl Boruta.Oauth.TokenApplication
  def token_success(conn, %Boruta.Oauth.TokenResponse{} = response) do
    # Boruta has no notion of an audience, so the RFC 8707 `resource` the client
    # asked for is recorded here, against the token it just received. Only the
    # two interfaces this server actually has are accepted; anything else is
    # ignored rather than bound, so a typo cannot mint a token good nowhere.
    origin = PublicOrigin.from_conn(conn)

    OAuth.bind_resource(
      response.access_token,
      conn.body_params["resource"],
      [origin, origin <> "/mcp"]
    )

    data =
      %{
        access_token: response.access_token,
        token_type: response.token_type,
        expires_in: response.expires_in,
        refresh_token: response.refresh_token,
        scope: response.token && response.token.scope
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    conn
    |> no_store()
    |> json(data)
  end

  @impl Boruta.Oauth.TokenApplication
  def token_error(conn, %Boruta.Oauth.Error{} = error) do
    conn
    |> put_status(error.status || :bad_request)
    |> json(%{
      error: to_string(error.error),
      error_description: error.error_description
    })
  end

  defp token_response(conn, {:ok, response}), do: conn |> no_store() |> json(response)

  defp token_response(conn, {:error, reason}) do
    conn
    |> put_status(400)
    |> json(%{error: to_string(reason), error_description: error_description(reason)})
  end

  defp error_description(:authorization_pending), do: "The user has not confirmed access yet."
  defp error_description(:slow_down), do: "Polling is faster than the advertised interval."
  defp error_description(:expired_token), do: "The claim has expired."
  defp error_description(_reason), do: "The credential could not be exchanged."

  # RFC 6749 section 5.1: a response carrying a credential must not be cached.
  defp no_store(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
  end

  defp auth_opts(conn) do
    [
      index: conn.private[:markdow_index] || Index.context(),
      issuer: PublicOrigin.from_conn(conn),
      api_key: conn.private[:markdow_api_key] || Application.get_env(:markdow, :api_key)
    ]
  end
end
