defmodule MarkdowWeb.IndexController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.Index
  alias Markdow.Operations
  alias MarkdowWeb.ApiSchemas.{ImportInput, Note, Status}

  tags ["Index"]
  security [%{"bearerAuth" => []}]

  plug MarkdowWeb.ApiAuth, scopes: ["notes:write"]

  operation :import,
    operation_id: "import_note",
    summary: "Import a Markdown file",
    parameters: [vault_id: [in: :path, type: :string, required: true]],
    request_body: {"Markdown file contents", "application/json", ImportInput},
    responses: [created: {"Imported note", "application/json", Note}]

  operation :rebuild,
    operation_id: "rebuild_index",
    summary: "Rebuild the index",
    parameters: [vault_id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Rebuilt", "application/json", Status}]

  def import(
        conn,
        %{"vault_id" => vault_id, "filename" => _filename, "body" => _body} = params
      ) do
    result =
      Operations.call(
        "import_note",
        Map.put(params, "vault_id", vault_id),
        index(conn),
        conn.assigns.authorization
      )

    MarkdowWeb.ApiResponse.send_result(conn, result, 201)
  end

  def import(conn, _params),
    do: MarkdowWeb.ApiResponse.send_result(conn, {:error, :invalid_arguments})

  def rebuild(conn, %{"vault_id" => vault_id}) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "rebuild_index",
        %{"vault_id" => vault_id},
        index(conn),
        conn.assigns.authorization
      )
    )
  end

  defp index(conn), do: conn.private[:markdow_index] || Index.context()
end
