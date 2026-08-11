defmodule MarkdowWeb.AccountApiTest do
  use Markdow.DataCase, async: true

  alias Markdow.DataCase

  test "creates a user with two isolated vaults", %{index: index} do
    user =
      index
      |> request(:post, "/users", %{
        "id" => "grace",
        "email" => "grace@example.com",
        "name" => "Grace"
      })
      |> json_response(201)

    assert user["id"] == "grace"

    assert index |> request(:get, "/users/grace", nil) |> json_response(200) == user

    first =
      index
      |> request(:post, "/users/grace/vaults", %{"id" => "journal", "name" => "Journal"})
      |> json_response(201)

    second =
      index
      |> request(:post, "/users/grace/vaults", %{"id" => "studio", "name" => "Studio"})
      |> json_response(201)

    assert first["user_id"] == user["id"]
    assert second["user_id"] == user["id"]

    vaults = index |> request(:get, "/users/grace/vaults", nil) |> json_response(200)
    assert Enum.map(vaults, & &1["id"]) == ["journal", "studio"]

    assert %{"id" => "today", "vault_id" => "journal"} =
             index
             |> request(:post, "/vaults/journal/notes", %{
               "id" => "today",
               "body" => "# Journal today\n\nPrivate apricot thought."
             })
             |> json_response(201)

    assert %{"id" => "today", "vault_id" => "studio"} =
             index
             |> request(:post, "/vaults/studio/notes", %{
               "id" => "today",
               "body" => "# Studio today\n\nPrivate blueberry thought."
             })
             |> json_response(201)

    journal_search =
      index
      |> request(:get, "/vaults/journal/search?q=apricot", nil)
      |> json_response(200)

    studio_search =
      index
      |> request(:get, "/vaults/studio/search?q=apricot", nil)
      |> json_response(200)

    assert Enum.map(journal_search, & &1["id"]) == ["today"]
    assert studio_search == []

    revocation =
      index
      |> request(:delete, "/users/grace/agent-credentials", nil)
      |> json_response(200)

    assert revocation == %{"revoked" => 0, "user_id" => "grace"}
  end

  defp request(index, method, path, body) do
    DataCase.endpoint_conn(method, path, body, index, "test")
  end

  defp json_response(conn, status) do
    assert conn.status == status
    JSON.decode!(conn.resp_body)
  end
end
