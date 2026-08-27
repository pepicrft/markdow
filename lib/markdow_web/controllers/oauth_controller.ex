defmodule MarkdowWeb.OAuthController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  @behaviour Boruta.Oauth.TokenApplication

  alias Markdow.AgentAuth
  alias Markdow.Index
  alias MarkdowWeb.PublicOrigin
  alias OpenApiSpex.Schema

  @claim_grant AgentAuth.claim_grant()
  @jwt_bearer_grant AgentAuth.jwt_bearer_grant()
  @client_credentials_grant "client_credentials"

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

  # Boruta reads the client credentials off the connection itself, from either
  # the basic authorization header or the form body, so the request is handed
  # over whole rather than destructured here.
  def token(conn, %{"grant_type" => grant}) when grant == @client_credentials_grant do
    Boruta.Oauth.token(conn, __MODULE__)
  end

  def token(conn, %{"grant_type" => _grant}) do
    conn |> put_status(400) |> json(%{error: "unsupported_grant_type"})
  end

  def token(conn, _params), do: conn |> put_status(400) |> json(%{error: "invalid_request"})

  def revoke(conn, %{"token" => token}) do
    case AgentAuth.revoke_access_token(token, auth_opts(conn)) do
      :ok -> send_resp(conn, 200, "")
      {:error, _reason} -> send_resp(conn, 200, "")
    end
  end

  def revoke(conn, _params), do: send_resp(conn, 200, "")

  @impl Boruta.Oauth.TokenApplication
  def token_success(conn, %Boruta.Oauth.TokenResponse{} = response) do
    json(conn, %{
      access_token: response.access_token,
      token_type: response.token_type,
      expires_in: response.expires_in,
      scope: response.token && response.token.scope
    })
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

  defp token_response(conn, {:ok, response}), do: json(conn, response)

  defp token_response(conn, {:error, reason}) do
    conn
    |> put_status(400)
    |> json(%{error: to_string(reason), error_description: error_description(reason)})
  end

  defp error_description(:authorization_pending), do: "The user has not confirmed access yet."
  defp error_description(:slow_down), do: "Polling is faster than the advertised interval."
  defp error_description(:expired_token), do: "The claim has expired."
  defp error_description(_reason), do: "The credential could not be exchanged."

  defp auth_opts(conn) do
    [
      index: conn.private[:markdow_index] || Index.context(),
      issuer: PublicOrigin.from_conn(conn),
      api_key: conn.private[:markdow_api_key] || Application.get_env(:markdow, :api_key)
    ]
  end
end
