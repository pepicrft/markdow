defmodule MarkdowWeb.SearchController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.Index
  alias Markdow.Operations
  alias MarkdowWeb.ApiSchemas.{Backlink, Graph, SearchResult}
  alias OpenApiSpex.Schema

  tags ["Notes"]
  security [%{"bearerAuth" => []}]

  plug MarkdowWeb.ApiAuth, scopes: ["notes:read"]

  operation :search,
    operation_id: "search_notes",
    summary: "Search notes",
    parameters: [
      vault_id: [in: :path, type: :string, required: true],
      q: [in: :query, type: :string, required: true],
      limit: [in: :query, type: :integer, required: false]
    ],
    responses: [
      ok: {"Search results", "application/json", %Schema{type: :array, items: SearchResult}}
    ]

  operation :backlinks,
    operation_id: "list_backlinks",
    summary: "List backlinks",
    parameters: [
      vault_id: [in: :path, type: :string, required: true],
      id: [in: :path, type: :string, required: true]
    ],
    responses: [
      ok: {"Backlinks", "application/json", %Schema{type: :array, items: Backlink}}
    ]

  operation :graph,
    operation_id: "get_note_graph",
    summary: "Get a linked-note graph",
    parameters: [
      vault_id: [in: :path, type: :string, required: true],
      id: [in: :path, type: :string, required: true],
      depth: [in: :query, type: :integer, required: false]
    ],
    responses: [ok: {"Linked-note graph", "application/json", Graph}]

  def search(conn, %{"vault_id" => _vault_id, "q" => _query} = params) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call("search_notes", params, index(conn), conn.assigns.authorization)
    )
  end

  def search(conn, _params),
    do: MarkdowWeb.ApiResponse.send_result(conn, {:error, :invalid_arguments})

  def backlinks(conn, %{"vault_id" => vault_id, "id" => id}) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "list_backlinks",
        %{"vault_id" => vault_id, "id" => id},
        index(conn),
        conn.assigns.authorization
      )
    )
  end

  def graph(conn, %{"vault_id" => vault_id, "id" => id} = params) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "get_note_graph",
        params |> Map.put("vault_id", vault_id) |> Map.put("id", id),
        index(conn),
        conn.assigns.authorization
      )
    )
  end

  defp index(conn), do: conn.private[:markdow_index] || Index.context()
end
