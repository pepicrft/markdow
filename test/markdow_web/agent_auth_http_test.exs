defmodule MarkdowWeb.AgentAuthHttpTest do
  use Markdow.DataCase, async: true

  alias Markdow.Accounts
  alias Markdow.AgentAuth
  alias Markdow.DataCase

  @email "agent-user@example.com"
  @password "correct horse battery staple"

  test "publishes a complete auth.md file and consistent discovery documents", %{index: index} do
    origin = DataCase.public_origin()
    auth_document = DataCase.endpoint_conn(:get, "/auth.md", nil, index)
    assert auth_document.status == 200
    assert auth_document.resp_body =~ "# auth.md"
    assert auth_document.resp_body =~ "POST #{origin}/agent/identity"
    assert auth_document.resp_body =~ AgentAuth.claim_grant()
    assert auth_document.resp_body =~ "sign in or create their account"
    assert auth_document.resp_body =~ "Call `list_users`"
    assert auth_document.resp_body =~ "Never call `create_user`"
    assert auth_document.resp_body =~ "call `create_vault`"
    assert auth_document.resp_body =~ "Do not use it to connect to MCP"
    assert auth_document.resp_body =~ "resource=#{origin}/mcp"
    assert auth_document.resp_body =~ "| `/oauth2/token` | `slow_down` |"

    protected =
      DataCase.endpoint_conn(:get, "/.well-known/oauth-protected-resource", nil, index)
      |> json_response(200)

    assert protected["resource"] == origin
    assert protected["scopes_supported"] == AgentAuth.scopes()

    mcp_protected =
      DataCase.endpoint_conn(
        :get,
        "/.well-known/oauth-protected-resource/mcp",
        nil,
        index
      )
      |> json_response(200)

    assert mcp_protected["resource"] == origin <> "/mcp"

    authorization =
      DataCase.endpoint_conn(:get, "/.well-known/oauth-authorization-server", nil, index)
      |> json_response(200)

    assert authorization["agent_auth"] == %{
             "claim_endpoint" => origin <> "/agent/identity/claim",
             "events_endpoint" => origin <> "/agent/event/notify",
             "events_supported" => [],
             "identity_assertion" => %{"assertion_types_supported" => []},
             "identity_endpoint" => origin <> "/agent/identity",
             "identity_types_supported" => ["service_auth"],
             "skill" => origin <> "/auth.md"
           }

    assert authorization["token_endpoint"] == origin <> "/oauth2/token"

    server_card =
      DataCase.endpoint_conn(:get, "/.well-known/mcp/server-card.json", nil, index)
      |> json_response(200)

    assert server_card["transport"]["url"] == origin <> "/mcp"

    jwks =
      DataCase.endpoint_conn(:get, "/.well-known/jwks.json", nil, index)
      |> json_response(200)

    assert [%{"use" => "sig"}] = jwks["keys"]
  end

  test "uses a self-hosted public origin throughout discovery and registration", %{index: index} do
    origin = "https://notes.example.net"

    auth_document = self_hosted_conn(:get, "/auth.md", nil, index, origin)
    assert auth_document.resp_body =~ "POST #{origin}/agent/identity"

    authorization =
      self_hosted_conn(:get, "/.well-known/oauth-authorization-server", nil, index, origin)
      |> json_response(200)

    assert authorization["issuer"] == origin
    assert authorization["agent_auth"]["skill"] == origin <> "/auth.md"

    registration =
      self_hosted_conn(
        :post,
        "/agent/identity",
        %{"type" => "service_auth", "login_hint" => "self-hosted@example.com"},
        index,
        origin
      )
      |> json_response(200)

    assert registration["claim"]["verification_uri"] =~
             origin <> "/agent/identity/claim"

    unauthorized =
      self_hosted_conn(:get, "/vaults/default/notes", nil, index, origin)

    assert Plug.Conn.get_resp_header(unauthorized, "www-authenticate") == [
             ~s(Bearer resource_metadata="#{origin}/.well-known/oauth-protected-resource", error="invalid_token", scope="notes:read")
           ]
  end

  test "signs up a user, confirms the claim, and limits the token to that user's vaults", %{
    index: index
  } do
    origin = DataCase.public_origin()
    registration = register(index, @email)
    assert registration["post_claim_scopes"] == AgentAuth.agent_scopes()
    assert registration["claim"]["user_code"] =~ ~r/^\d{6}$/

    {claim_path, claim_attempt_token} = claim_location(registration)
    claim_page = DataCase.browser_conn(:get, claim_path, nil, index)
    assert claim_page.status == 200
    assert claim_page.resp_body =~ "Sign in or create your account"
    assert claim_page.resp_body =~ "Already use Markdow?"
    assert claim_page.resp_body =~ "New to Markdow?"
    assert claim_page.resp_body =~ @email
    assert claim_page.resp_body =~ ~s(name="_csrf_token")
    assert Plug.Conn.get_resp_header(claim_page, "cache-control") == ["no-store"]
    assert Plug.Conn.get_resp_header(claim_page, "referrer-policy") == ["no-referrer"]

    assert [content_policy] =
             Plug.Conn.get_resp_header(claim_page, "content-security-policy")

    assert content_policy =~ "form-action 'self'"
    assert content_policy =~ "frame-ancestors 'none'"

    assert claim_poll(index, registration) |> Map.fetch!("error") == "authorization_pending"
    assert claim_poll(index, registration) |> Map.fetch!("error") == "slow_down"

    signup =
      DataCase.browser_conn(
        :post,
        "/agent/identity/claim/sign-up",
        %{
          "claim_attempt_token" => claim_attempt_token,
          "name" => "Agent User",
          "password" => @password
        },
        index
      )

    assert signup.status == 303
    user_id = Plug.Conn.get_session(signup, :markdow_user_id)
    assert is_binary(user_id)

    session = %{markdow_user_id: user_id}
    verification_pending = DataCase.browser_conn(:get, claim_path, nil, index, session)
    assert verification_pending.status == 200
    assert verification_pending.resp_body =~ "Verify your email"

    assert_receive {:email, verification_email}
    verification_url = verification_email.text_body |> verification_url() |> URI.parse()
    verification_params = URI.decode_query(verification_url.query)

    verification_page =
      DataCase.browser_conn(
        :get,
        verification_url.path <> "?" <> verification_url.query,
        nil,
        index
      )

    assert verification_page.status == 200
    assert verification_page.resp_body =~ "Verify your email"
    assert verification_page.resp_body =~ @email

    verified =
      DataCase.browser_conn(
        :post,
        verification_url.path,
        verification_params,
        index
      )

    assert verified.status == 303
    session = %{markdow_user_id: Plug.Conn.get_session(verified, :markdow_user_id)}

    confirmation_page = DataCase.browser_conn(:get, claim_path, nil, index, session)
    assert confirmation_page.status == 200
    assert confirmation_page.resp_body =~ "Confirm agent access"
    assert confirmation_page.resp_body =~ @email

    rejected =
      DataCase.browser_conn(
        :post,
        "/agent/identity/claim/confirm",
        %{"claim_attempt_token" => claim_attempt_token, "user_code" => "000000"},
        index,
        session
      )

    assert rejected.status == 422
    assert rejected.resp_body =~ "That code is invalid or has expired."

    confirmation =
      DataCase.browser_conn(
        :post,
        "/agent/identity/claim/confirm",
        %{
          "claim_attempt_token" => claim_attempt_token,
          "user_code" => registration["claim"]["user_code"]
        },
        index,
        session
      )

    assert confirmation.status == 200
    assert confirmation.resp_body =~ "Access confirmed"

    token = claim_poll(index, registration, 200)
    assert token["token_type"] == "Bearer"
    assert is_binary(token["identity_assertion"])
    refute String.contains?(token["scope"], "users:write")

    users =
      DataCase.endpoint_conn(:get, "/users", nil, index, token["access_token"])
      |> json_response(200)

    assert [%{"id" => ^user_id, "email" => @email}] = users

    own_vault =
      DataCase.endpoint_conn(
        :post,
        "/users/#{user_id}/vaults",
        %{"id" => "agent-vault", "name" => "Agent vault"},
        index,
        token["access_token"]
      )
      |> json_response(201)

    assert own_vault["user_id"] == user_id

    assert DataCase.endpoint_conn(
             :get,
             "/vaults/default/notes",
             nil,
             index,
             token["access_token"]
           ).status == 403

    refreshed =
      DataCase.form_conn(
        "/oauth2/token",
        %{
          "grant_type" => AgentAuth.jwt_bearer_grant(),
          "assertion" => token["identity_assertion"],
          "resource" => origin <> "/mcp"
        },
        index
      )
      |> json_response(200)

    assert DataCase.endpoint_conn(:get, "/users", nil, index, refreshed["access_token"]).status ==
             401

    mcp_result =
      DataCase.endpoint_conn(
        :post,
        "/mcp",
        %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{
            "name" => "list_vaults",
            "arguments" => %{"user_id" => user_id}
          }
        },
        index,
        refreshed["access_token"]
      )
      |> json_response(200)

    assert get_in(mcp_result, ["result", "structuredContent", "result"]) == [own_vault]

    assert DataCase.form_conn(
             "/oauth2/revoke",
             %{"token" => token["access_token"], "token_type_hint" => "access_token"},
             index
           ).status == 200

    assert DataCase.endpoint_conn(:get, "/users", nil, index, token["access_token"]).status == 401
    assert DataCase.browser_conn(:get, claim_path, nil, index).resp_body =~ "Access confirmed"
  end

  test "requires an exact signed-in email at render and submit time", %{index: index} do
    assert {:ok, attacker} =
             Accounts.claim_user(
               "attacker@example.com",
               "Attacker",
               @password,
               index.repo
             )

    registration = register(index, @email)
    {claim_path, claim_attempt_token} = claim_location(registration)
    attacker_session = %{markdow_user_id: attacker.id}

    mismatch_page = DataCase.browser_conn(:get, claim_path, nil, index, attacker_session)
    assert mismatch_page.status == 403
    assert mismatch_page.resp_body =~ "Use the requested account"

    mismatch_submit =
      DataCase.browser_conn(
        :post,
        "/agent/identity/claim/confirm",
        %{
          "claim_attempt_token" => claim_attempt_token,
          "user_code" => registration["claim"]["user_code"]
        },
        index,
        attacker_session
      )

    assert mismatch_submit.status == 403
    assert mismatch_submit.resp_body =~ "different email address"
    assert claim_poll(index, registration) |> Map.fetch!("error") == "authorization_pending"
  end

  test "signs an existing user in without disclosing their password", %{index: index} do
    assert {:ok, existing} = Accounts.claim_user(@email, "Existing", @password, index.repo)
    registration = register(index, @email)
    {claim_path, claim_attempt_token} = claim_location(registration)

    page = DataCase.browser_conn(:get, claim_path, nil, index)
    assert page.resp_body =~ "Sign in or create your account"
    assert page.resp_body =~ "Already use Markdow?"
    assert page.resp_body =~ "New to Markdow?"
    assert page.resp_body =~ "Your name"

    rejected =
      DataCase.browser_conn(
        :post,
        "/agent/identity/claim/sign-in",
        %{"claim_attempt_token" => claim_attempt_token, "password" => "wrong-password"},
        index
      )

    assert rejected.status == 422
    assert rejected.resp_body =~ "password is incorrect"
    refute rejected.resp_body =~ @password

    accepted =
      DataCase.browser_conn(
        :post,
        "/agent/identity/claim/sign-in",
        %{"claim_attempt_token" => claim_attempt_token, "password" => @password},
        index
      )

    assert accepted.status == 303
    assert Plug.Conn.get_session(accepted, :markdow_user_id) == existing.id
  end

  test "cannot convert an operator-created account into an agent account", %{index: index} do
    assert {:ok, seeded} =
             Accounts.create_user(
               %{"email" => @email, "name" => "Operator-created"},
               index.repo
             )

    registration = register(index, @email)
    {_claim_path, claim_attempt_token} = claim_location(registration)

    response =
      DataCase.browser_conn(
        :post,
        "/agent/identity/claim/sign-up",
        %{
          "claim_attempt_token" => claim_attempt_token,
          "name" => "Attacker",
          "password" => @password
        },
        index
      )

    assert response.status == 422
    assert response.resp_body =~ "could not be used to create an account"
    assert Plug.Conn.get_session(response, :markdow_user_id) == nil
    assert {:ok, unchanged} = Accounts.get_user(seeded.id, index.repo)
    assert unchanged.name == "Operator-created"
  end

  test "returns stable errors for unsupported or malformed protocol requests", %{index: index} do
    assert DataCase.endpoint_conn(:post, "/agent/identity", %{"type" => "anonymous"}, index)
           |> json_response(400) == %{"error" => "anonymous_not_enabled"}

    invalid_login =
      DataCase.endpoint_conn(
        :post,
        "/agent/identity",
        %{"type" => "service_auth", "login_hint" => "not-an-email"},
        index
      )
      |> json_response(400)

    assert invalid_login["error"] == "invalid_login_hint"

    assert DataCase.endpoint_conn(:post, "/agent/identity", %{}, index)
           |> json_response(400) == %{"error" => "invalid_request"}

    assert DataCase.endpoint_conn(:post, "/agent/identity/claim", %{}, index)
           |> json_response(400) == %{"error" => "anonymous_not_enabled"}

    unsupported_grant =
      DataCase.form_conn("/oauth2/token", %{"grant_type" => "unsupported"}, index)
      |> json_response(400)

    assert unsupported_grant["error"] == "unsupported_grant_type"

    assert DataCase.form_conn("/oauth2/token", %{}, index) |> json_response(400) ==
             %{"error" => "invalid_request"}

    assert DataCase.form_conn("/oauth2/revoke", %{}, index).status == 200

    event =
      DataCase.endpoint_conn(:post, "/agent/event/notify", %{}, index)
      |> json_response(400)

    assert event["err"] == "unsupported_event"
    assert DataCase.browser_conn(:get, "/agent/identity/claim", nil, index).status == 404
  end

  test "ignores a stale browser session during a new claim", %{index: index} do
    registration = register(index, @email)
    {claim_path, _claim_attempt_token} = claim_location(registration)

    page =
      DataCase.browser_conn(
        :get,
        claim_path,
        nil,
        index,
        %{markdow_user_id: "deleted-user"}
      )

    assert page.status == 200
    assert page.resp_body =~ "Sign in or create your account"
  end

  test "rejects claim form submissions without a cross-site request forgery token", %{
    index: index
  } do
    conn =
      :post
      |> Plug.Test.conn(
        "/agent/identity/claim/sign-in",
        URI.encode_query(%{
          "claim_attempt_token" => "cla_untrusted",
          "password" => @password
        })
      )
      |> Plug.Conn.put_private(:markdow_index, index)
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_req_header("accept", "text/html")
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      MarkdowWeb.Endpoint.call(conn, [])
    end
  end

  defp register(index, email) do
    DataCase.endpoint_conn(
      :post,
      "/agent/identity",
      %{"type" => "service_auth", "login_hint" => email},
      index
    )
    |> json_response(200)
  end

  defp claim_location(registration) do
    uri = URI.parse(registration["claim"]["verification_uri"])

    {uri.path <> "?" <> uri.query,
     uri.query |> URI.decode_query() |> Map.fetch!("claim_attempt_token")}
  end

  defp claim_poll(index, registration, status \\ 400) do
    DataCase.form_conn(
      "/oauth2/token",
      %{"grant_type" => AgentAuth.claim_grant(), "claim_token" => registration["claim_token"]},
      index
    )
    |> json_response(status)
  end

  defp json_response(conn, status) do
    assert conn.status == status, conn.resp_body
    JSON.decode!(conn.resp_body)
  end

  defp verification_url(body) do
    ~r{https?://[^\s]+/agent/identity/claim/verify-email\?[^\s]+}
    |> Regex.run(body)
    |> List.first()
  end

  defp self_hosted_conn(method, path, body, index, origin) do
    conn =
      if is_nil(body),
        do: Plug.Test.conn(method, path),
        else: Plug.Test.conn(method, path, JSON.encode!(body))

    conn
    |> Plug.Conn.put_private(:markdow_index, index)
    |> Plug.Conn.put_private(:markdow_api_key, "test")
    |> Plug.Conn.put_private(:markdow_public_origin, origin)
    |> Plug.Conn.put_private(:markdow_rate_limit_namespace, inspect(index.storage))
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> then(fn conn ->
      if is_nil(body),
        do: conn,
        else: Plug.Conn.put_req_header(conn, "content-type", "application/json")
    end)
    |> MarkdowWeb.Endpoint.call([])
  end
end
