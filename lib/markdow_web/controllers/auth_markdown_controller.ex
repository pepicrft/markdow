defmodule MarkdowWeb.AuthMarkdownController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.AgentAuth
  alias MarkdowWeb.PublicOrigin
  alias OpenApiSpex.Schema

  tags ["Agent authentication"]
  security []

  operation :show,
    operation_id: "agent_auth_instructions",
    summary: "Read the auth.md agent registration instructions",
    responses: [ok: {"auth.md", "text/markdown", %Schema{type: :string}}]

  def show(conn, _params) do
    origin = PublicOrigin.from_conn(conn)

    document = """
    # auth.md

    Markdow supports agent registration for its headless Markdown service. The resource server and authorization server are both `#{origin}`. The structured protected resource metadata is authoritative if it differs from this document.

    ## 1. Discover

    A protected request without a credential returns:

    ```http
    HTTP/1.1 401 Unauthorized
    WWW-Authenticate: Bearer resource_metadata="#{origin}/.well-known/oauth-protected-resource"
    ```

    Fetch `#{origin}/.well-known/oauth-protected-resource` for the Representational State Transfer ([REST](https://developer.mozilla.org/en-US/docs/Glossary/REST)) interface, or `#{origin}/.well-known/oauth-protected-resource/mcp` for the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) server. Read `resource`, `resource_name`, `authorization_servers`, `scopes_supported`, and `bearer_methods_supported`.

    Fetch the first authorization server at `#{origin}/.well-known/oauth-authorization-server`. Read `issuer`, `token_endpoint`, `revocation_endpoint`, `grant_types_supported`, and the complete `agent_auth` object. It describes `skill`, `identity_endpoint`, `claim_endpoint`, `events_endpoint`, `identity_types_supported`, `identity_assertion.assertion_types_supported`, and `events_supported`.

    ## 2. Pick a method

    Markdow supports `service_auth`. Use it when the user gives you their email and consents to connect. The user will sign in or create their account on a Markdow-owned page before access is granted.

    `identity_assertion` and `anonymous` are not enabled. Their registration errors are `identity_assertion_not_enabled` and `anonymous_not_enabled`.

    Use the claim ceremony when a person is present to approve the connection. It is the only way to gain access to an account for the first time, and the access token it returns lasts an hour and cannot be refreshed.

    Use a registered client, in section 9, when a service has to keep working without anyone there to approve it again. Registering requires a credential that already has access to the account, so it grants nothing new: it turns access somebody already approved into a credential that can be presented again tomorrow.

    ## 3. Register with service_auth

    ```http
    POST #{origin}/agent/identity
    Content-Type: application/json

    {"type":"service_auth","login_hint":"user@example.com"}
    ```

    A successful response has this complete shape and does not contain an access token or identity assertion:

    ```json
    {
      "registration_id": "reg_...",
      "registration_type": "service_auth",
      "claim_url": "#{origin}/agent/identity/claim",
      "claim_token": "clm_...",
      "claim_token_expires": "2026-08-12T12:00:00Z",
      "post_claim_scopes": ["users:read", "vaults:read", "vaults:write", "notes:read", "notes:write", "documents:read", "documents:write", "embeddings:read", "embeddings:write", "mcp"],
      "claim": {
        "user_code": "123456",
        "expires_in": 600,
        "verification_uri": "#{origin}/agent/identity/claim?claim_attempt_token=cla_...",
        "interval": 5
      }
    }
    ```

    Keep `claim_token` private and in memory until the ceremony finishes. Show `claim.user_code` and `claim.verification_uri` to the user in one message. Tell the user to open the link, sign in or create their account, verify the account email, and enter the code there. Never ask the user to send the code back to you. Markdow never emails this code.

    ## 4. Complete the claim ceremony

    The user opens `verification_uri`. Markdow requires a password-based sign-in or sign-up for exactly the normalized `login_hint` email. For an unverified account, Markdow emails a separate one-time link to that address. Opening the email link displays a confirmation page; only the explicit form submission verifies the email, so automated link previews do not consume it. The email link expires after 15 minutes and can be used once.

    The signed-in account and its verified email are checked when the claim page is rendered and checked again when the code is submitted. A different or unverified account cannot complete the claim. Successful identity assertions carry `email_verified: true`; Markdow never asserts an unverified address as an identity.

    Poll no faster than `claim.interval`:

    ```http
    POST #{origin}/oauth2/token
    Content-Type: application/x-www-form-urlencoded

    grant_type=#{AgentAuth.claim_grant()}&claim_token=<claim_token>
    ```

    While confirmation is pending:

    ```json
    {"error":"authorization_pending","error_description":"The user has not confirmed access yet."}
    ```

    Success returns:

    ```json
    {
      "access_token": "mat_...",
      "token_type": "Bearer",
      "expires_in": 3600,
      "scope": "users:read vaults:read vaults:write notes:read notes:write documents:read documents:write embeddings:read embeddings:write mcp",
      "identity_assertion": "eyJ...",
      "assertion_expires": "2026-08-12T12:00:00Z"
    }
    ```

    The access token in this claim response is bound to `#{origin}` for the REST interface. Do not use it to connect to MCP. If the requested work uses MCP, immediately exchange `identity_assertion` as shown below with `resource=#{origin}/mcp`, then configure the MCP client with the new token.

    ## 5. Exchange the identity assertion

    Markdow uses the JavaScript Object Notation Web Token ([JSON Web Token](https://www.rfc-editor.org/rfc/rfc7519)) bearer grant. Exchange the same `identity_assertion` for a new access token until the assertion expires. Markdow never issues a refresh token.

    ```http
    POST #{origin}/oauth2/token
    Content-Type: application/x-www-form-urlencoded

    grant_type=#{AgentAuth.jwt_bearer_grant()}&assertion=<identity_assertion>&resource=#{origin}/mcp
    ```

    Use `resource=#{origin}` for the REST interface and `resource=#{origin}/mcp` for MCP. A token is accepted only by the resource for which it was issued.

    ```json
    {
      "access_token": "mat_...",
      "token_type": "Bearer",
      "expires_in": 3600,
      "scope": "users:read vaults:read vaults:write notes:read notes:write documents:read documents:write embeddings:read embeddings:write mcp"
    }
    ```

    ## 6. Use the access token and create the first vault

    Send `Authorization: Bearer <access_token>`. The [OpenAPI](https://www.openapis.org/) document is at `#{origin}/openapi.json`, interactive documentation is at `#{origin}/docs`, and MCP is at `#{origin}/mcp`.

    The account already exists after the user completes sign-up. Call `list_users`; an agent token returns only its authenticated user. Call `list_vaults` with that user's identifier. If there is no vault, ask the user for its name and call `create_vault`. Never call `create_user` during this flow.

    To migrate an Obsidian vault, call `write_document` once per relative path. Encode the original bytes as Base64 in `data_base64`. Markdown paths ending in `.md` are indexed for search, backlinks, and graphs. Every other file is stored byte-for-byte. Preserve directories, Unicode, spaces, and filename case. Do not upload `.git` or secret-bearing files unless the user explicitly asks. Use `list_documents`, `read_document`, and `delete_document` for the same paths.

    ## 7. Errors

    | Endpoint | Error | Agent action |
    | --- | --- | --- |
    | `/agent/identity` | `invalid_request` or `invalid_login_hint` | Correct the request. |
    | `/agent/identity` | `anonymous_not_enabled` or `identity_assertion_not_enabled` | Use `service_auth`. |
    | `/agent/identity` | `rate_limited` | Wait before registering again. |
    | Claim page | `invalid_claim_token`, `account_mismatch`, or `expired_token` | Tell the user to use the exact link and account, or restart registration. |
    | `/oauth2/token` | `authorization_pending` | Continue polling at the advertised interval. |
    | `/oauth2/token` | `slow_down` | Wait at least the advertised interval before polling again. |
    | `/oauth2/token` | `expired_token` | Restart registration. |
    | `/oauth2/token` | `invalid_grant` | Restart registration or correct the resource. |
    | `/oauth2/token` | `unsupported_grant_type` | Use an advertised grant type. |
    | Protected resource | `invalid_token` | Obtain a token for this resource. |
    | Protected resource | `insufficient_scope` or `forbidden` | Do not attempt an operation outside the authenticated account. |

    ## 8. Revoke credentials

    Credential revocation follows [Request for Comments 7009](https://www.rfc-editor.org/rfc/rfc7009). It is idempotent. The identity assertion remains exchangeable until it expires.

    ```http
    POST #{origin}/oauth2/revoke
    Content-Type: application/x-www-form-urlencoded

    token=<access_token>&token_type_hint=access_token
    ```

    An operator can revoke every agent token and identity assertion for a user through the `revoke_agent_credentials` REST and MCP operation. Markdow does not advertise provider security events because `identity_assertion` registration is not enabled.

    ## 9. Register a client

    Client registration follows [Request for Comments 7591](https://www.rfc-editor.org/rfc/rfc7591) and answers two different asks depending on whether you present a credential.

    **Without one**, you get a public client for the authorization code flow. Send `redirect_uris`. There is no secret, and the client is bound to no account: on its own it can reach nothing at all. It becomes useful only once somebody signs in at `#{origin}/oauth2/authorize` and approves it, and only for the account that approved. This is the path an interactive client takes.

    ```http
    POST #{origin}/oauth2/register
    Content-Type: application/json

    {"client_name": "Your application", "redirect_uris": ["https://example.com/callback"]}
    ```

    Then send the person to the authorization endpoint. Proof key for code exchange is required, not optional, and only `S256` is accepted.

    ```
    GET #{origin}/oauth2/authorize
      ?response_type=code
      &client_id=<client_id>
      &redirect_uri=<redirect_uri>
      &scope=mcp notes:read notes:write
      &code_challenge=<challenge>
      &code_challenge_method=S256
      &resource=#{origin}/mcp
    ```

    They sign in on a Markdow page and see what you are asking for before deciding. Your application never sees the password. Exchange the returned code with the verifier you committed to:

    ```http
    POST #{origin}/oauth2/token
    Content-Type: application/x-www-form-urlencoded

    grant_type=authorization_code&client_id=<client_id>&code=<code>&redirect_uri=<redirect_uri>&code_verifier=<verifier>
    ```

    The resulting token acts for the person who approved it, whoever registered the client.

    **With a credential**, you get a confidential client for the client credentials grant, described below. That one acts on its own with nobody present, which is why registering it takes a credential that already has access. An access token from the claim ceremony registers a client for the account it belongs to. An application key stands for the deployment rather than a person, so it must name the account with `markdow_user_id`.

    ```http
    POST #{origin}/oauth2/register
    Authorization: Bearer <access_token>
    Content-Type: application/json

    {"client_name": "hermes"}
    ```

    The response carries `client_id` and `client_secret`. The secret is shown once and never expires. Store it the way you would store a password.

    Exchange it for an access token whenever you need one. There is no refresh token because there is no need for one: the client authenticates itself again.

    ```http
    POST #{origin}/oauth2/token
    Content-Type: application/x-www-form-urlencoded

    grant_type=client_credentials&client_id=<client_id>&client_secret=<client_secret>&scope=mcp notes:read notes:write&resource=#{origin}/mcp
    ```

    Send `resource` to bind the token to one interface, following [Request for Comments 8707](https://www.rfc-editor.org/rfc/rfc8707). Use `#{origin}/mcp` for the Model Context Protocol server and `#{origin}` for everything else. A bound token is refused at the other interface. A token requested without `resource` is not bound and reaches both, so ask for the narrower one.

    A registered client can only ever reach the account it was registered for. It cannot create accounts, it cannot register further clients, and it cannot act as a person: `authorization_code` and the password grant are not offered, so there is no flow in which a client speaks for a user who never signed in.

    ## 10. See and revoke registered clients

    A secret never expires, so deleting the client is what revokes it. Deleting revokes the tokens it was issued at the same time.

    ```http
    GET #{origin}/users/<user_id>/oauth-clients
    DELETE #{origin}/users/<user_id>/oauth-clients/<client_id>
    ```

    The listing never returns secrets. Deleting requires `users:write`, which no agent token and no registered client is granted, so a leaked client credential cannot be used to delete the evidence or to remove a client somebody else relies on.

    A single access token can also be handed back through the revocation endpoint in section 8, which accepts both kinds of credential.

    ## Granted scopes

    - `users:read`: read the authenticated user.
    - `vaults:read`: read that user's vaults.
    - `vaults:write`: create a vault for that user.
    - `notes:read`: list, read, search, and traverse notes in that user's vaults.
    - `notes:write`: create, update, import, delete, and rebuild notes in that user's vaults.
    - `documents:read`: list and read path-preserving Markdown and non-Markdown documents.
    - `documents:write`: create, replace, and delete path-preserving documents.
    - `embeddings:read`: inspect that user's redacted embedding configuration.
    - `embeddings:write`: configure, validate, use, and delete that user's embedding configuration. The account supplies its own endpoint, model, and credential, and the endpoint must speak the OpenAI embeddings protocol over https.
    - `mcp`: connect to the MCP server with an MCP-bound token.

    `users:write` is reserved for an operator application key and is never granted to an agent registration.

    ## Service information

    #{service_information(origin)}
    """

    conn
    |> put_resp_content_type("text/markdown", "utf-8")
    |> send_resp(200, document)
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
