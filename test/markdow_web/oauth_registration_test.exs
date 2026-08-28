defmodule MarkdowWeb.OAuthRegistrationTest do
  use Markdow.DataCase, async: true

  alias Boruta.Ecto.Admin
  alias Markdow.Accounts
  alias Markdow.DataCase

  setup %{index: index} do
    {:ok, owner} =
      Accounts.create_user(
        %{"id" => "owner", "email" => "owner@example.com", "name" => "Owner"},
        index.repo
      )

    {:ok, stranger} =
      Accounts.create_user(
        %{"id" => "stranger", "email" => "stranger@example.com", "name" => "Stranger"},
        index.repo
      )

    {:ok, vault} =
      Accounts.create_vault(
        owner.id,
        %{"id" => "owner-vault", "name" => "Owner vault"},
        index.repo
      )

    {:ok, stranger_vault} =
      Accounts.create_vault(
        stranger.id,
        %{"id" => "stranger-vault", "name" => "Stranger vault"},
        index.repo
      )

    {:ok, owner: owner, vault: vault, stranger_vault: stranger_vault}
  end

  test "a public client exchanges a proof-key authorization code bound to the signed-in user", %{
    index: index,
    owner: owner,
    vault: vault,
    stranger_vault: stranger_vault
  } do
    redirect_uri = "https://client.example/callback"
    client = register(index, redirect_uri)
    assert client["client_id"]
    refute client["client_secret"]
    assert client["grant_types"] == ["authorization_code", "refresh_token"]
    assert client["token_endpoint_auth_method"] == "none"

    stored_client = Admin.get_client!(client["client_id"])
    assert stored_client.confidential == false
    assert stored_client.pkce
    assert stored_client.public_refresh_token
    assert stored_client.public_revoke
    assert stored_client.token_endpoint_auth_methods == []
    refute "client_credentials" in stored_client.supported_grant_types

    verifier = String.duplicate("markdow-proof-key-", 4)
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    query = %{
      "response_type" => "code",
      "client_id" => client["client_id"],
      "redirect_uri" => redirect_uri,
      "state" => "client-state",
      "scope" => "documents:write documents:read",
      "code_challenge" => challenge,
      "code_challenge_method" => "S256"
    }

    authorization_path = "/oauth2/authorize?" <> URI.encode_query(query)

    consent =
      DataCase.browser_conn(:get, authorization_path, nil, index, %{markdow_user_id: owner.id})

    assert consent.status == 200
    assert consent.resp_body =~ "Confirm access"
    assert consent.resp_body =~ "documents:read"
    assert consent.resp_body =~ ~s(<div data-part="authorization-actions">)
    assert consent.resp_body =~ ~s(<form method="post" action="/oauth2/authorize">)

    assert consent.resp_body =~
             ~s(<form method="post" action="/oauth2/authorize/deny" data-part="deny">)

    plain_proof_request =
      DataCase.browser_conn(
        :get,
        "/oauth2/authorize?" <>
          URI.encode_query(%{
            "response_type" => "code",
            "client_id" => client["client_id"],
            "redirect_uri" => redirect_uri,
            "scope" => "documents:read",
            "code_challenge" => verifier,
            "code_challenge_method" => "plain"
          }),
        nil,
        index,
        %{markdow_user_id: owner.id}
      )

    assert plain_proof_request.status == 400
    assert plain_proof_request.resp_body =~ "S256 proof-key challenge is required"

    denied = DataCase.browser_conn(:post, "/oauth2/authorize/deny", query, index)
    assert denied.status == 302
    denied_location = denied |> Plug.Conn.get_resp_header("location") |> List.first()
    assert denied_location =~ "error=access_denied"
    assert denied_location =~ "state=client-state"

    approval =
      DataCase.browser_conn(
        :post,
        "/oauth2/authorize",
        Map.put(query, "consent", "approve"),
        index,
        %{markdow_user_id: owner.id}
      )

    assert approval.status == 302, approval.resp_body
    location = approval |> Plug.Conn.get_resp_header("location") |> List.first()
    redirect = URI.parse(location)
    params = URI.decode_query(redirect.query)

    assert redirect_uri == URI.to_string(%{redirect | query: nil})
    assert params["state"] == "client-state"
    assert params["code"]

    rejected =
      DataCase.form_conn(
        "/oauth2/token",
        %{
          "grant_type" => "authorization_code",
          "client_id" => client["client_id"],
          "redirect_uri" => redirect_uri,
          "code" => params["code"],
          "code_verifier" => "not-the-proof-key"
        },
        index
      )

    assert rejected.status == 400
    assert json(rejected)["error"] == "invalid_request"

    token =
      DataCase.form_conn(
        "/oauth2/token",
        %{
          "grant_type" => "authorization_code",
          "client_id" => client["client_id"],
          "redirect_uri" => redirect_uri,
          "code" => params["code"],
          "code_verifier" => verifier
        },
        index
      )
      |> json()

    assert token["access_token"]
    assert token["refresh_token"]

    assert DataCase.endpoint_conn(
             :put,
             "/vaults/#{vault.id}/documents/Notes/Owned.md",
             %{"data_base64" => Base.encode64("# owned\n")},
             index,
             token["access_token"]
           ).status == 200

    assert DataCase.endpoint_conn(
             :put,
             "/vaults/#{stranger_vault.id}/documents/Notes/Forbidden.md",
             %{"data_base64" => Base.encode64("# forbidden\n")},
             index,
             token["access_token"]
           ).status == 403
  end

  test "an unsigned authorization request goes through email sign-in", %{index: index} do
    client = register(index, "https://client.example/callback")
    verifier = String.duplicate("email-login-proof-key-", 3)
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

    response =
      DataCase.browser_conn(
        :get,
        "/oauth2/authorize?" <>
          URI.encode_query(%{
            "response_type" => "code",
            "client_id" => client["client_id"],
            "redirect_uri" => "https://client.example/callback",
            "scope" => "notes:read",
            "code_challenge" => challenge,
            "code_challenge_method" => "S256"
          }),
        nil,
        index
      )

    assert response.status == 302
    assert Plug.Conn.get_resp_header(response, "location") == ["/accounts/log-in"]
  end

  defp register(index, redirect_uri) do
    DataCase.endpoint_conn(
      :post,
      "/oauth2/register",
      %{
        "client_name" => "Markdow test client",
        "redirect_uris" => [redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      },
      index
    )
    |> json()
  end

  defp json(conn), do: JSON.decode!(conn.resp_body)
end
