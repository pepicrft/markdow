defmodule MarkdowWeb.OAuthAuthorizeController do
  @moduledoc false

  @behaviour Boruta.Oauth.AuthorizeApplication

  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Boruta.ClientsAdapter
  alias Boruta.Oauth.{AuthorizationSuccess, AuthorizeResponse, Client, Error, ResourceOwner}
  alias MarkdowWeb.UserAuth
  alias OpenApiSpex.Schema

  @max_state_length 1_000
  @consent_fields ~w(response_type client_id redirect_uri state scope resource code_challenge code_challenge_method nonce)

  tags ["Authentication"]
  security []

  operation :authorize,
    operation_id: "authorize_oauth_client",
    summary: "Authorize a client for the signed-in user",
    parameters: [client_id: [in: :query, type: :string, required: true]],
    responses: [found: {"Authorization result", "text/html", %Schema{type: :string}}]

  operation :approve,
    operation_id: "approve_oauth_client",
    summary: "Approve an OAuth client authorization request",
    request_body:
      {"Authorization approval", "application/x-www-form-urlencoded",
       %Schema{type: :object, additionalProperties: true}},
    responses: [found: {"Authorization result", "text/html", %Schema{type: :string}}]

  operation :deny,
    operation_id: "deny_oauth_client",
    summary: "Deny an OAuth client authorization request",
    request_body:
      {"Authorization denial", "application/x-www-form-urlencoded",
       %Schema{type: :object, additionalProperties: true}},
    responses: [found: {"Authorization denial", "text/html", %Schema{type: :string}}]

  def authorize(%{assigns: %{current_user: %{id: id, email: email}}} = conn, params) do
    case validate_request(params) do
      :ok ->
        Boruta.Oauth.preauthorize(conn, %ResourceOwner{sub: id, username: email}, __MODULE__)

      {:error, description} ->
        invalid_request(conn, description)
    end
  end

  def authorize(conn, _params) do
    conn
    |> UserAuth.store_return_to()
    |> redirect(to: "/accounts/log-in")
    |> halt()
  end

  def approve(
        %{assigns: %{current_user: %{id: id, email: email}}} = conn,
        %{"consent" => "approve"} = params
      ) do
    case validate_request(params) do
      :ok ->
        request_conn = %{conn | query_params: Map.take(params, @consent_fields)}
        Boruta.Oauth.authorize(request_conn, %ResourceOwner{sub: id, username: email}, __MODULE__)

      {:error, description} ->
        invalid_request(conn, description)
    end
  end

  def approve(conn, _params),
    do: invalid_request(conn, "The authorization request was not approved.")

  def deny(conn, params) do
    with :ok <- validate_request(params),
         %Client{} = client <- ClientsAdapter.get_client(params["client_id"]),
         redirect_uri when is_binary(redirect_uri) and redirect_uri != "" <-
           params["redirect_uri"],
         :ok <- Client.check_redirect_uri(client, redirect_uri) do
      redirect(
        conn,
        external:
          redirect_uri <>
            if(String.contains?(redirect_uri, "?"), do: "&", else: "?") <>
            URI.encode_query(%{
              "error" => "access_denied",
              "error_description" => "The account holder did not approve this request.",
              "state" => params["state"] || ""
            })
      )
    else
      _error -> invalid_request(conn, "The authorization request is invalid.")
    end
  end

  @impl true
  def preauthorize_success(conn, %AuthorizationSuccess{} = response) do
    send_page(conn, 200, consent_page(response, conn.params))
  end

  @impl true
  def preauthorize_error(conn, %Error{} = error), do: authorize_error(conn, error)

  @impl true
  def authorize_success(conn, %AuthorizeResponse{} = response),
    do: redirect(conn, external: AuthorizeResponse.redirect_to_url(response))

  @impl true
  def authorize_error(conn, %Error{format: format} = error) when not is_nil(format),
    do: redirect(conn, external: Error.redirect_to_url(error))

  def authorize_error(conn, %Error{} = error), do: invalid_request(conn, error.error_description)

  defp validate_request(params) do
    cond do
      byte_size(params["state"] || "") > @max_state_length ->
        {:error, "The state parameter is too long."}

      params["code_challenge_method"] != "S256" ->
        {:error, "An S256 proof-key challenge is required."}

      not valid_code_challenge?(params["code_challenge"]) ->
        {:error, "The proof-key challenge is invalid."}

      true ->
        :ok
    end
  end

  # An S256 challenge is the unpadded Base64 URL encoding of a SHA-256 hash.
  # Its fixed form keeps the advertised Proof Key for Code Exchange method from
  # silently falling back to the weaker plain-text variant.
  defp valid_code_challenge?(challenge) when is_binary(challenge),
    do: byte_size(challenge) == 43 and challenge =~ ~r/\A[A-Za-z0-9_-]+\z/

  defp valid_code_challenge?(_challenge), do: false

  defp consent_page(response, params) do
    fields =
      @consent_fields
      |> Enum.map_join(fn field ->
        case Map.fetch(params, field) do
          {:ok, value} when is_binary(value) ->
            ~s(<input type="hidden" name="#{field}" value="#{escape(value)}">)

          _missing ->
            ""
        end
      end)

    scopes = response.scope |> to_string() |> String.split() |> Enum.map_join(", ", &escape/1)
    client_name = response.client.name || "This application"

    MarkdowWeb.Theme.inject("""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="robots" content="noindex,nofollow">
        <title>Confirm access · Markdow</title>
        <style>
          /* markdow-theme */
          body { margin: 0; background: var(--paper); color: var(--ink); font-family: var(--serif); line-height: var(--leading-normal); }
          main { width: min(560px, calc(100% - 48px)); margin: 0 auto; padding: var(--space-11) 0; }
          h1 { margin: 0 0 var(--space-4); font: var(--text-heading)/var(--leading-tight) var(--sans); }
          p { margin: 0 0 var(--space-6); color: var(--muted); }
          dl { margin: 0 0 var(--space-7); padding: var(--space-5); background: var(--wash); }
          dt { font: var(--weight-semibold) var(--text-label)/var(--leading-snug) var(--sans); }
          dd { margin: var(--space-1) 0 var(--space-5); }
          dd:last-child { margin-bottom: 0; }
          button { border: var(--rule-width) solid var(--accent); padding: var(--space-4) var(--space-6); background: var(--accent); color: var(--ink-inverted); font: var(--weight-semibold) var(--text-label)/var(--leading-flat) var(--sans); cursor: pointer; }
        </style>
      </head>
      <body>
        <main>
          <h1>Confirm access</h1>
          <p>#{escape(client_name)} is requesting access to the vaults owned by your signed-in account.</p>
          <dl>
            <dt>Signed in as</dt>
            <dd>#{escape(response.resource_owner.username)}</dd>
            <dt>Requested access</dt>
            <dd>#{scopes}</dd>
          </dl>
          <form method="post" action="/oauth2/authorize">
            #{csrf_field()}
            #{fields}
            <input type="hidden" name="consent" value="approve">
            <button type="submit">Allow access</button>
          </form>
          <form method="post" action="/oauth2/authorize/deny">
            #{csrf_field()}
            #{fields}
            <button type="submit">Do not allow access</button>
          </form>
        </main>
      </body>
    </html>
    """)
  end

  defp invalid_request(conn, description) do
    conn
    |> put_status(:bad_request)
    |> send_page(:bad_request, error_page(description))
  end

  defp error_page(description),
    do: "<h1>Authorization unavailable</h1><p>#{escape(description)}</p>"

  defp csrf_field,
    do:
      ~s(<input type="hidden" name="_csrf_token" value="#{Plug.CSRFProtection.get_csrf_token()}">)

  defp send_page(conn, status, body) do
    conn
    |> put_resp_content_type("text/html", "utf-8")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header(
      "content-security-policy",
      "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
    )
    |> send_resp(status, body)
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
