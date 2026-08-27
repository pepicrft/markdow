defmodule MarkdowWeb.OAuthRegistrationTest do
  # Boruta caches clients in a process-wide Nebulex instance that does not roll
  # back with the sandbox, so these run one at a time.
  use Markdow.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Markdow.Accounts
  alias Markdow.DataCase
  alias Markdow.OAuth.ClientOwner
  alias Markdow.Repo

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

  test "registers a client, issues it a token, and lets it reach its own vault", %{
    index: index,
    vault: vault
  } do
    registered = register(index, %{"client_name" => "hermes", "markdow_user_id" => "owner"})

    assert registered.status == 201
    client = json(registered)

    assert is_binary(client["client_id"])
    assert is_binary(client["client_secret"])
    assert client["grant_types"] == ["client_credentials"]
    # Nothing ages the secret out. Deleting the client is what revokes it.
    assert client["client_secret_expires_at"] == 0

    token = token(index, client, "documents:write documents:read")

    assert is_binary(token["access_token"])
    assert token["token_type"] in ["bearer", "Bearer"]

    written =
      DataCase.endpoint_conn(
        :put,
        "/vaults/#{vault.id}/documents/Notes/Machine.md",
        %{"data_base64" => Base.encode64("# From a registered client\n")},
        index,
        token["access_token"]
      )

    assert written.status == 200
    assert json(written)["path"] == "Notes/Machine.md"
  end

  test "a registered client cannot reach an account it was not registered for", %{
    index: index,
    stranger_vault: stranger_vault
  } do
    client = index |> register(%{"markdow_user_id" => "owner"}) |> json()
    token = token(index, client, "documents:write")

    written =
      DataCase.endpoint_conn(
        :put,
        "/vaults/#{stranger_vault.id}/documents/Trespass.md",
        %{"data_base64" => Base.encode64("nope")},
        index,
        token["access_token"]
      )

    assert written.status == 403
  end

  test "a client whose account binding is gone is refused rather than unscoped", %{
    index: index,
    vault: vault
  } do
    client = index |> register(%{"markdow_user_id" => "owner"}) |> json()
    token = token(index, client, "documents:write")

    # The binding is the client's whole authority. Losing it must close the door
    # rather than leave a token that answers to no account.
    client_id = client["client_id"]
    {1, _} = Repo.delete_all(from(o in ClientOwner, where: o.client_id == ^client_id))

    written =
      DataCase.endpoint_conn(
        :put,
        "/vaults/#{vault.id}/documents/Orphan.md",
        %{"data_base64" => Base.encode64("nope")},
        index,
        token["access_token"]
      )

    assert written.status == 401
  end

  test "refuses to register without a credential", %{index: index} do
    response =
      DataCase.endpoint_conn(
        :post,
        "/oauth2/register",
        %{"client_name" => "anonymous"},
        index,
        nil
      )

    assert response.status == 401
  end

  test "refuses an application key registration that names no account", %{index: index} do
    response = register(index, %{"client_name" => "unbound"})

    assert response.status == 400
    assert json(response)["error"] == "invalid_client_metadata"
  end

  test "refuses an application key registration naming an account that does not exist", %{
    index: index
  } do
    response = register(index, %{"markdow_user_id" => "nobody"})

    assert response.status == 400
    assert json(response)["error"] == "invalid_client_metadata"
  end

  test "refuses a token request that presents the wrong secret", %{index: index} do
    client = index |> register(%{"markdow_user_id" => "owner"}) |> json()

    response =
      DataCase.form_conn(
        "/oauth2/token",
        %{
          "grant_type" => "client_credentials",
          "client_id" => client["client_id"],
          "client_secret" => "not-the-secret",
          "scope" => "documents:write"
        },
        index
      )

    assert response.status in [400, 401]
    assert json(response)["error"] == "invalid_client"
  end

  test "advertises the registration endpoint and the grant", %{index: index} do
    metadata =
      :get
      |> DataCase.endpoint_conn("/.well-known/oauth-authorization-server", nil, index)
      |> json()

    assert metadata["registration_endpoint"] == DataCase.public_origin() <> "/oauth2/register"
    assert "client_credentials" in metadata["grant_types_supported"]
    assert "client_secret_post" in metadata["token_endpoint_auth_methods_supported"]
  end

  test "a registered client can call the stateless Model Context Protocol endpoint", %{
    index: index
  } do
    client = index |> register(%{"markdow_user_id" => "owner"}) |> json()
    token = token(index, client, "mcp vaults:read")

    response =
      DataCase.endpoint_conn(
        :post,
        "/mcp",
        %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}},
        index,
        token["access_token"]
      )

    assert response.status == 200
    assert Plug.Conn.get_resp_header(response, "mcp-session-id") == []
    assert json(response)["result"]["serverInfo"]["name"] == "markdow"
  end

  test "a registered client stores a note over Model Context Protocol without a session", %{
    index: index,
    vault: vault
  } do
    client = index |> register(%{"markdow_user_id" => "owner"}) |> json()
    token = token(index, client, "mcp notes:write notes:read")

    # No initialize first and no session header on either call. If anything were
    # being held between requests, the write would not be able to stand alone.
    written =
      mcp(index, token, 1, "create_note", %{
        "vault_id" => vault.id,
        "id" => "from-hermes",
        "body" => "# Stored by a registered client\n"
      })

    assert written["structuredContent"]["result"]["id"] == "from-hermes"

    read =
      mcp(index, token, 2, "get_note", %{"vault_id" => vault.id, "id" => "from-hermes"})

    assert read["structuredContent"]["result"]["body"] =~ "Stored by a registered client"
  end

  test "a registered client is refused a Model Context Protocol tool outside its scopes", %{
    index: index,
    vault: vault
  } do
    client = index |> register(%{"markdow_user_id" => "owner"}) |> json()
    token = token(index, client, "mcp notes:read")

    result =
      mcp(index, token, 1, "create_note", %{
        "vault_id" => vault.id,
        "id" => "unauthorized",
        "body" => "should not be written"
      })

    assert result["isError"]
    assert hd(result["content"])["text"] == "insufficient_scope"
  end

  defp mcp(index, token, id, tool, arguments) do
    DataCase.endpoint_conn(
      :post,
      "/mcp",
      %{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => "tools/call",
        "params" => %{"name" => tool, "arguments" => arguments}
      },
      index,
      token["access_token"]
    )
    |> json()
    |> Map.fetch!("result")
  end

  defp register(index, params),
    do: DataCase.endpoint_conn(:post, "/oauth2/register", params, index, "test")

  defp token(index, client, scope) do
    DataCase.form_conn(
      "/oauth2/token",
      %{
        "grant_type" => "client_credentials",
        "client_id" => client["client_id"],
        "client_secret" => client["client_secret"],
        "scope" => scope
      },
      index
    )
    |> json()
  end

  defp json(conn), do: JSON.decode!(conn.resp_body)
end
