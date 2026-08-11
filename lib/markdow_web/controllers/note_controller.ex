defmodule MarkdowWeb.NoteController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.Index
  alias Markdow.Operations
  alias MarkdowWeb.ApiSchemas.{DeletedNote, Note, NoteInput, NoteList}

  tags ["Notes"]
  security [%{"bearerAuth" => []}]

  plug MarkdowWeb.ApiAuth, [scopes: ["notes:read"]] when action in [:index, :show]
  plug MarkdowWeb.ApiAuth, [scopes: ["notes:write"]] when action not in [:index, :show]

  operation :index,
    operation_id: "list_notes",
    summary: "List notes",
    parameters: [
      vault_id: [in: :path, type: :string, required: true],
      limit: [in: :query, type: :integer, required: false],
      offset: [in: :query, type: :integer, required: false]
    ],
    responses: [ok: {"Paginated notes", "application/json", NoteList}]

  operation :show,
    operation_id: "get_note",
    summary: "Get a note",
    parameters: [
      vault_id: [in: :path, type: :string, required: true],
      id: [in: :path, type: :string, required: true]
    ],
    responses: [ok: {"Note", "application/json", Note}]

  operation :create,
    operation_id: "create_note",
    summary: "Create a note",
    parameters: [vault_id: [in: :path, type: :string, required: true]],
    request_body: {"Note", "application/json", NoteInput},
    responses: [created: {"Created note", "application/json", Note}]

  operation :update,
    operation_id: "update_note",
    summary: "Update a note",
    parameters: [
      vault_id: [in: :path, type: :string, required: true],
      id: [in: :path, type: :string, required: true]
    ],
    request_body: {"Note", "application/json", NoteInput},
    responses: [ok: {"Updated note", "application/json", Note}]

  operation :delete,
    operation_id: "delete_note",
    summary: "Delete a note",
    parameters: [
      vault_id: [in: :path, type: :string, required: true],
      id: [in: :path, type: :string, required: true]
    ],
    responses: [ok: {"Deleted note", "application/json", DeletedNote}]

  def index(conn, %{"vault_id" => vault_id} = params) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "list_notes",
        Map.put(params, "vault_id", vault_id),
        index(conn),
        conn.assigns.authorization
      )
    )
  end

  def show(conn, %{"vault_id" => vault_id, "id" => id}) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "get_note",
        %{"vault_id" => vault_id, "id" => id},
        index(conn),
        conn.assigns.authorization
      )
    )
  end

  def create(conn, %{"vault_id" => vault_id} = params) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "create_note",
        Map.put(params, "vault_id", vault_id),
        index(conn),
        conn.assigns.authorization
      ),
      201
    )
  end

  def update(conn, %{"vault_id" => vault_id, "id" => id} = params) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "update_note",
        params |> Map.put("vault_id", vault_id) |> Map.put("id", id),
        index(conn),
        conn.assigns.authorization
      )
    )
  end

  def delete(conn, %{"vault_id" => vault_id, "id" => id}) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "delete_note",
        %{"vault_id" => vault_id, "id" => id},
        index(conn),
        conn.assigns.authorization
      )
    )
  end

  defp index(conn), do: conn.private[:markdow_index] || Index.context()
end
