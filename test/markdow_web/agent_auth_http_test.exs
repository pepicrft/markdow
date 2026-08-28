defmodule MarkdowWeb.AgentAuthHttpTest do
  use Markdow.DataCase, async: true

  alias Markdow.Accounts
  alias Markdow.DataCase

  @email "agent-user@example.com"

  test "documents the email-link authorization-code flow", %{index: index} do
    origin = DataCase.public_origin()
    document = DataCase.endpoint_conn(:get, "/auth.md", nil, index)

    assert document.status == 200
    assert document.resp_body =~ "Proof Key for Code Exchange"
    assert document.resp_body =~ "POST #{origin}/oauth2/register"
    assert document.resp_body =~ "#{origin}/oauth2/authorize"
    assert document.resp_body =~ "one-time sign-in link"

    metadata =
      DataCase.endpoint_conn(:get, "/.well-known/oauth-authorization-server", nil, index)
      |> json()

    assert metadata["authorization_endpoint"] == origin <> "/oauth2/authorize"
    assert metadata["grant_types_supported"] == ["authorization_code", "refresh_token"]
    assert metadata["code_challenge_methods_supported"] == ["S256"]
    assert metadata["token_endpoint_auth_methods_supported"] == ["none"]
  end

  test "emails a link, authenticates its owner, and confirms only that owner's claim", %{
    index: index
  } do
    index = %{index | email_notifier: __MODULE__.Mailbox}
    registration = register(index, @email)
    claim_token = registration["claim_token"]
    claim_path = registration["claim"]["verification_uri"] |> URI.parse() |> request_path()
    claim_attempt_token = claim_path |> URI.parse() |> query_value("claim_attempt_token")

    pending = DataCase.browser_conn(:get, claim_path, nil, index)
    assert pending.status == 200
    assert pending.resp_body =~ "Check your email"
    refute pending.resp_body =~ "password"
    assert Plug.Conn.get_resp_header(pending, "cache-control") == ["no-store"]

    assert_receive {:email_link, @email, login_url}
    login_path = login_url |> URI.parse() |> request_path()

    assert {:ok, owner} = Accounts.get_user_by_email(@email, index.repo)

    authenticated =
      DataCase.browser_conn(
        :get,
        login_path,
        nil,
        index,
        %{markdow_user_return_to: claim_path}
      )

    assert Plug.Conn.get_resp_header(authenticated, "location") == [claim_path]
    assert {:ok, verified_owner} = Accounts.get_user(owner.id, index.repo)
    assert %DateTime{} = verified_owner.email_verified_at

    confirmation =
      DataCase.browser_conn(
        :get,
        claim_path,
        nil,
        index,
        %{markdow_user_id: owner.id}
      )

    assert confirmation.status == 200
    assert confirmation.resp_body =~ "Confirm agent access"

    confirmed =
      DataCase.browser_conn(
        :post,
        "/agent/identity/claim/confirm",
        %{"claim_attempt_token" => claim_attempt_token},
        index,
        %{markdow_user_id: owner.id}
      )

    assert confirmed.status == 200
    assert confirmed.resp_body =~ "Access confirmed"

    token =
      DataCase.form_conn(
        "/oauth2/token",
        %{
          "grant_type" => "urn:workos:agent-auth:grant-type:claim",
          "claim_token" => claim_token
        },
        index
      )
      |> json()

    assert token["access_token"]
  end

  defp register(index, email) do
    DataCase.endpoint_conn(
      :post,
      "/agent/identity",
      %{"type" => "service_auth", "login_hint" => email},
      index
    )
    |> json()
  end

  defp request_path(%URI{path: path, query: nil}), do: path
  defp request_path(%URI{path: path, query: query}), do: path <> "?" <> query

  defp query_value(path, key),
    do: path |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!(key)

  defp json(conn), do: JSON.decode!(conn.resp_body)

  defmodule Mailbox do
    @behaviour Markdow.Accounts.EmailNotifier

    @impl true
    def deliver_login_link(user, url) do
      send(self(), {:email_link, user.email, url})
      {:ok, %{to: user.email}}
    end

    @impl true
    def deliver_verification(_user, _url), do: {:ok, %{}}
  end
end
