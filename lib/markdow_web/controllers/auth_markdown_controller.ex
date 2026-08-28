defmodule MarkdowWeb.AuthMarkdownController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.OAuth
  alias MarkdowWeb.PublicOrigin
  alias OpenApiSpex.Schema

  tags ["Authentication"]
  security []

  operation :show,
    operation_id: "oauth_instructions",
    summary: "Read OAuth authorization instructions",
    responses: [ok: {"auth.md", "text/markdown", %Schema{type: :string}}]

  def show(conn, _params) do
    origin = PublicOrigin.from_conn(conn)

    document = """
    # auth.md

    Markdow is a multi-tenant, headless Markdown service. Access is authorized for one signed-in user at a time, and every vault operation verifies that the token subject owns the vault.

    ## Discover

    A protected request without a credential returns:

    ```http
    HTTP/1.1 401 Unauthorized
    WWW-Authenticate: Bearer resource_metadata="#{origin}/.well-known/oauth-protected-resource"
    ```

    Fetch `#{origin}/.well-known/oauth-protected-resource` for the [Representational State Transfer (REST)](https://developer.mozilla.org/en-US/docs/Glossary/REST) interface or `#{origin}/.well-known/oauth-protected-resource/mcp` for the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) server. Then fetch `#{origin}/.well-known/oauth-authorization-server` for the authorization, token, revocation, and client-registration endpoints.

    ## Register a public client

    Markdow supports dynamic client registration under [Request for Comments 7591](https://www.rfc-editor.org/rfc/rfc7591). Register a public client before beginning the browser flow. No client secret is issued.

    ```http
    POST #{origin}/oauth2/register
    Content-Type: application/json

    {"client_name":"My agent","redirect_uris":["https://client.example/callback"],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none"}
    ```

    ## Request user authorization

    Create a high-entropy verifier and derive an `S256` challenge as defined by [Proof Key for Code Exchange](https://www.rfc-editor.org/rfc/rfc7636). Open this address in the user's browser:

    ```text
    #{origin}/oauth2/authorize?response_type=code&client_id=<client_id>&redirect_uri=<registered_redirect_uri>&scope=mcp%20vaults:read%20notes:read&resource=#{origin}/mcp&state=<state>&code_challenge=<S256_challenge>&code_challenge_method=S256
    ```

    If the user is not signed in, Markdow asks for their email and sends a one-time sign-in link. Opening the link authenticates that email address. Markdow then shows the requested scopes and requires an explicit confirmation before redirecting to the registered callback with a short-lived authorization code.

    ## Exchange the authorization code

    Exchange the code and the original verifier. A public client authenticates this request with its `client_id` and the verifier, not a shared secret.

    ```http
    POST #{origin}/oauth2/token
    Content-Type: application/x-www-form-urlencoded

    grant_type=authorization_code&client_id=<client_id>&redirect_uri=<registered_redirect_uri>&code=<authorization_code>&code_verifier=<verifier>&resource=#{origin}/mcp
    ```

    The response contains a short-lived access token and, when requested by the registered client, a refresh token. Send `Authorization: Bearer <access_token>` to Markdow. The token is bound to the signed-in user, so it can reach only that user's vaults.

    Use `resource=#{origin}/mcp` for the Model Context Protocol server and `resource=#{origin}` for the REST interface. Binding a token to one resource prevents it from being replayed at the other interface.

    ## Revoke a token

    Revocation follows [Request for Comments 7009](https://www.rfc-editor.org/rfc/rfc7009) and is idempotent:

    ```http
    POST #{origin}/oauth2/revoke
    Content-Type: application/x-www-form-urlencoded

    token=<access_token>&token_type_hint=access_token
    ```

    ## Granted scopes

    #{scopes()}

    ## Service information

    #{service_information(origin)}
    """

    conn
    |> put_resp_content_type("text/markdown", "utf-8")
    |> send_resp(200, document)
  end

  defp scopes do
    OAuth.scopes()
    |> Enum.map_join("\n", fn scope -> "- `#{scope}`" end)
  end

  defp service_information(origin) do
    legal_links =
      if Application.get_env(:markdow, :marketing_routes, true) do
        """
        - Terms: #{origin}/terms
        - Privacy: #{origin}/privacy
        """
      else
        "- Legal terms and privacy information are provided by this self-hosted service's operator."
      end

    """
    - Service: #{origin}
    - Pricing: self-hosted local mode has no service charge.
    #{legal_links}
    - Integration help: https://github.com/pepicrft/markdow/issues
    """
  end
end
