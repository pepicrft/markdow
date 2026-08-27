defmodule MarkdowWeb.OAuthAuthorizeTest do
  use Markdow.DataCase, async: true

  alias Markdow.Accounts
  alias Markdow.DataCase
  alias Markdow.Repo

  @password "correct horse battery staple"
  @redirect "https://claude.ai/api/mcp/auth_callback"

  setup %{index: index} do
    {:ok, user} =
      Accounts.claim_user("owner@example.com", "Owner", @password, index.repo)

    # The claim flow verifies the address before it hands anything out, and
    # approving a client is held to the same bar.
    Repo.update_all(Markdow.Accounts.User, set: [email_verified_at: DateTime.utc_now()])

    {:ok, vault} =
      Accounts.create_vault(user.id, %{"id" => "owner-vault", "name" => "Owner"}, index.repo)

    {:ok, user: user, vault: vault}
  end

  test "a client registers with no credential and is given nothing until somebody approves it",
       %{index: index, vault: vault} do
    client = register(index)

    assert client["grant_types"] == ["authorization_code"]
    # A public client is handed no secret at all. Proof key for code exchange is
    # what protects its code, and saying otherwise would tell the client it is
    # confidential when it is not.
    assert client["token_endpoint_auth_method"] == "none"
    refute Map.has_key?(client, "client_secret")

    verifier = "a-verifier-long-enough-to-be-worth-something-0123456789"
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    # Nobody has approved anything yet, so the client cannot get a token.
    refused =
      DataCase.form_conn(
        "/oauth2/token",
        %{
          "grant_type" => "authorization_code",
          "client_id" => client["client_id"],
          "code" => "invented",
          "redirect_uri" => @redirect,
          "code_verifier" => verifier
        },
        index
      )

    assert refused.status in [400, 401]

    code = approve(index, client, challenge)
    token = exchange(index, client, code, verifier)

    assert is_binary(token["access_token"])

    read =
      DataCase.endpoint_conn(
        :get,
        "/vaults/#{vault.id}/documents",
        nil,
        index,
        token["access_token"]
      )

    assert read.status == 200
  end

  test "the token acts for the person who approved, not for whoever registered", %{
    index: index,
    user: user
  } do
    client = register(index)
    verifier = "another-verifier-that-is-plenty-long-0123456789abcdef"
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    code = approve(index, client, challenge)
    token = exchange(index, client, code, verifier)

    listed =
      :get
      |> DataCase.endpoint_conn("/users", nil, index, token["access_token"])
      |> json()

    assert Enum.map(listed, & &1["id"]) == [user.id]
  end

  test "the code cannot be exchanged without the verifier that was committed to", %{index: index} do
    client = register(index)
    verifier = "the-real-verifier-0123456789abcdefghijklmnop"
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    code = approve(index, client, challenge)

    stolen =
      DataCase.form_conn(
        "/oauth2/token",
        %{
          "grant_type" => "authorization_code",
          "client_id" => client["client_id"],
          "code" => code,
          "redirect_uri" => @redirect,
          "code_verifier" => "not-the-verifier-that-was-committed-to"
        },
        index
      )

    assert stolen.status in [400, 401]
  end

  test "a code is good once", %{index: index} do
    client = register(index)
    verifier = "single-use-verifier-0123456789abcdefghijklmnop"
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    code = approve(index, client, challenge)
    assert is_binary(exchange(index, client, code, verifier)["access_token"])

    replayed =
      DataCase.form_conn(
        "/oauth2/token",
        %{
          "grant_type" => "authorization_code",
          "client_id" => client["client_id"],
          "code" => code,
          "redirect_uri" => @redirect,
          "code_verifier" => verifier
        },
        index
      )

    assert replayed.status in [400, 401]
  end

  test "the authorize page asks for a sign in before it asks for anything else", %{index: index} do
    client = register(index)

    page =
      DataCase.browser_conn(
        :get,
        "/oauth2/authorize?" <>
          URI.encode_query(%{
            "client_id" => client["client_id"],
            "redirect_uri" => @redirect,
            "response_type" => "code"
          }),
        nil,
        index
      )

    assert page.status == 200
    assert page.resp_body =~ "Sign in"
    assert page.resp_body =~ "password"
    refute page.resp_body =~ "Connect</button>"
  end

  test "the consent page names the client and what it is asking for", %{index: index} do
    client = register(index, "Claude")

    page =
      DataCase.browser_conn(
        :post,
        "/oauth2/authorize/sign-in",
        %{
          "email" => "owner@example.com",
          "password" => @password,
          "client_id" => client["client_id"],
          "redirect_uri" => @redirect,
          "response_type" => "code",
          "scope" => "mcp notes:read"
        },
        index
      )

    assert page.status == 200
    assert page.resp_body =~ "Claude"
    assert page.resp_body =~ "Read and search your notes"
    assert page.resp_body =~ "Connect over the Model Context Protocol"
    assert page.resp_body =~ "owner@example.com"
  end

  test "a wrong password does not sign anybody in", %{index: index} do
    client = register(index)

    page =
      DataCase.browser_conn(
        :post,
        "/oauth2/authorize/sign-in",
        %{
          "email" => "owner@example.com",
          "password" => "wrong",
          "client_id" => client["client_id"],
          "redirect_uri" => @redirect,
          "response_type" => "code"
        },
        index
      )

    assert page.status == 200
    assert page.resp_body =~ "did not match"
    refute page.resp_body =~ "Connect</button>"
  end

  test "refusing sends the client away empty handed", %{index: index} do
    client = register(index)

    denied =
      DataCase.browser_conn(
        :post,
        "/oauth2/authorize/deny",
        %{
          "client_id" => client["client_id"],
          "redirect_uri" => @redirect,
          "response_type" => "code",
          "state" => "xyz"
        },
        index
      )

    assert denied.status == 302
    location = Plug.Conn.get_resp_header(denied, "location") |> hd()
    assert location =~ "error=access_denied"
    assert location =~ "state=xyz"
  end

  test "a publicly registered client cannot use the client credentials grant", %{index: index} do
    client = register(index)

    response =
      DataCase.form_conn(
        "/oauth2/token",
        %{
          "grant_type" => "client_credentials",
          "client_id" => client["client_id"],
          "client_secret" => client["client_secret"] || "",
          "scope" => "notes:read"
        },
        index
      )

    assert response.status in [400, 401]
  end

  test "discovery advertises the interactive flow", %{index: index} do
    metadata =
      :get
      |> DataCase.endpoint_conn("/.well-known/oauth-authorization-server", nil, index)
      |> json()

    assert metadata["authorization_endpoint"] == DataCase.public_origin() <> "/oauth2/authorize"
    assert "authorization_code" in metadata["grant_types_supported"]
    assert metadata["response_types_supported"] == ["code"]
    assert metadata["code_challenge_methods_supported"] == ["S256"]
  end

  defp register(index, name \\ "A client") do
    :post
    |> DataCase.endpoint_conn(
      "/oauth2/register",
      %{"client_name" => name, "redirect_uris" => [@redirect]},
      index,
      nil
    )
    |> json()
  end

  defp approve(index, client, challenge) do
    signed_in =
      DataCase.browser_conn(
        :post,
        "/oauth2/authorize/sign-in",
        %{
          "email" => "owner@example.com",
          "password" => @password,
          "client_id" => client["client_id"],
          "redirect_uri" => @redirect,
          "response_type" => "code",
          "scope" => "mcp notes:read documents:read users:read",
          "code_challenge" => challenge,
          "code_challenge_method" => "S256"
        },
        index
      )

    assert signed_in.status == 200

    approved =
      DataCase.browser_conn(
        :post,
        "/oauth2/authorize/approve",
        %{
          "client_id" => client["client_id"],
          "redirect_uri" => @redirect,
          "response_type" => "code",
          "scope" => "mcp notes:read documents:read users:read",
          "code_challenge" => challenge,
          "code_challenge_method" => "S256"
        },
        index,
        Plug.Conn.get_session(signed_in)
      )

    assert approved.status == 302, approved.resp_body
    location = approved |> Plug.Conn.get_resp_header("location") |> hd()
    assert location =~ @redirect

    location
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
    |> Map.fetch!("code")
  end

  defp exchange(index, client, code, verifier) do
    DataCase.form_conn(
      "/oauth2/token",
      %{
        "grant_type" => "authorization_code",
        "client_id" => client["client_id"],
        "code" => code,
        "redirect_uri" => @redirect,
        "code_verifier" => verifier
      },
      index
    )
    |> json()
  end

  defp json(conn), do: JSON.decode!(conn.resp_body)
end
