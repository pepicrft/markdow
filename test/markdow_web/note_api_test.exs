defmodule MarkdowWeb.NoteApiTest do
  use Markdow.DataCase, async: true

  import Plug.Conn

  alias Markdow.DataCase

  @vault_path "/vaults/default"

  test "health is public and note routes advertise auth.md discovery", %{index: index} do
    origin = DataCase.public_origin()
    health = DataCase.endpoint_conn(:get, "/health", nil, index)
    assert health.status == 200
    assert JSON.decode!(health.resp_body) == %{"status" => "ok"}

    unauthorized = DataCase.endpoint_conn(:get, @vault_path <> "/notes", nil, index)
    assert unauthorized.status == 401

    assert get_resp_header(unauthorized, "www-authenticate") == [
             ~s(Bearer resource_metadata="#{origin}/.well-known/oauth-protected-resource", error="invalid_token", scope="notes:read")
           ]
  end

  test "creates, reads, lists, searches, traverses, updates, and deletes notes", %{index: index} do
    target =
      index
      |> request(:post, @vault_path <> "/notes", %{
        "id" => "architecture",
        "body" => "# Architecture\n\nPostgreSQL search lives here."
      })
      |> json_response(201)

    assert target["title"] == "Architecture"

    source =
      index
      |> request(:post, @vault_path <> "/notes", %{
        "id" => "plan",
        "body" => "# Plan\n\nReview [[Architecture]] first."
      })
      |> json_response(201)

    assert source["links"] == [
             %{
               "target_id" => "architecture",
               "context" => "Review [[Architecture]] first."
             }
           ]

    listed = index |> request(:get, @vault_path <> "/notes", nil) |> json_response(200)
    assert listed["pagination"]["total"] == 2

    fetched = index |> request(:get, @vault_path <> "/notes/plan", nil) |> json_response(200)
    assert fetched["body"] =~ "Architecture"

    search =
      index
      |> request(:get, @vault_path <> "/search?q=PostgreSQL", nil)
      |> json_response(200)

    assert Enum.map(search, & &1["id"]) == ["architecture"]

    backlinks =
      index
      |> request(:get, @vault_path <> "/notes/architecture/backlinks", nil)
      |> json_response(200)

    assert Enum.map(backlinks, & &1["id"]) == ["plan"]

    graph =
      index
      |> request(:get, @vault_path <> "/notes/plan/graph?depth=2", nil)
      |> json_response(200)

    assert Enum.map(graph["nodes"], & &1["id"]) == ["plan", "architecture"]

    updated =
      index
      |> request(:put, @vault_path <> "/notes/plan", %{
        "body" => "# Updated plan\n\nNo links."
      })
      |> json_response(200)

    assert updated["title"] == "Updated plan"
    assert updated["links"] == []

    deleted =
      index
      |> request(:delete, @vault_path <> "/notes/plan", nil)
      |> json_response(200)

    assert deleted == %{"vault_id" => "default", "id" => "plan", "deleted" => true}
    assert request(index, :get, @vault_path <> "/notes/plan", nil).status == 404
  end

  test "rebuilds an index through the protected route", %{index: index} do
    response = request(index, :post, @vault_path <> "/index/rebuild", %{})
    assert json_response(response, 200) == %{"status" => "rebuilt"}
  end

  test "imports Markdown contents through the protected route", %{index: index} do
    imported =
      index
      |> request(:post, @vault_path <> "/notes/import", %{
        "filename" => "Imported Note.md",
        "body" => "# Imported note\n\nUploaded through the note interface."
      })
      |> json_response(201)

    assert imported["id"] == "Imported Note"
    assert imported["path"] == "Imported Note"
    assert imported["body"] =~ "Uploaded through"
  end

  test "maps invalid requests and storage conflicts to stable errors", %{index: index} do
    invalid_search = request(index, :get, @vault_path <> "/search", nil)
    assert json_response(invalid_search, 422) == %{"error" => "invalid_arguments"}

    assert %{"id" => "first"} =
             index
             |> request(:post, @vault_path <> "/notes", %{
               "id" => "first",
               "path" => "shared/path",
               "body" => "# First"
             })
             |> json_response(201)

    conflict =
      request(index, :post, @vault_path <> "/notes", %{
        "id" => "second",
        "path" => "shared/path",
        "body" => "# Second"
      })

    assert json_response(conflict, 422) == %{"error" => "invalid_arguments"}
  end

  defp request(index, method, path, body) do
    DataCase.endpoint_conn(method, path, body, index, "test")
  end

  defp json_response(conn, status) do
    assert conn.status == status
    JSON.decode!(conn.resp_body)
  end
end
