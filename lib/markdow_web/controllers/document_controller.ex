defmodule MarkdowWeb.DocumentController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.Index
  alias Markdow.Operations
  alias MarkdowWeb.ApiSchemas.{DeletedDocument, Document, DocumentContent}
  alias OpenApiSpex.Schema

  tags ["Documents"]
  security [%{"bearerAuth" => []}]

  plug MarkdowWeb.ApiAuth, [scopes: ["documents:read"]] when action in [:index, :show]
  plug MarkdowWeb.ApiAuth, [scopes: ["documents:write"]] when action in [:write, :delete]

  operation :index,
    operation_id: "list_documents",
    summary: "List vault documents",
    parameters: [vault_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Documents", "application/json", %Schema{type: :array, items: Document}}
    ]

  operation :show,
    operation_id: "read_document",
    summary: "Read a vault document without changing its bytes",
    parameters: [
      vault_id: [in: :path, type: :string, required: true],
      path: [in: :path, type: :string, required: true]
    ],
    responses: [ok: {"Document content", "application/json", DocumentContent}]

  operation :write,
    operation_id: "write_document",
    summary: "Create or replace a vault document",
    parameters: [
      vault_id: [in: :path, type: :string, required: true],
      path: [in: :path, type: :string, required: true]
    ],
    request_body:
      {"Document content", "application/json",
       %Schema{
         type: :object,
         properties: %{data_base64: %Schema{type: :string, format: :byte}},
         required: [:data_base64],
         additionalProperties: false
       }},
    responses: [ok: {"Stored document", "application/json", Document}]

  operation :delete,
    operation_id: "delete_document",
    summary: "Delete a vault document",
    parameters: [
      vault_id: [in: :path, type: :string, required: true],
      path: [in: :path, type: :string, required: true]
    ],
    responses: [ok: {"Deleted document", "application/json", DeletedDocument}]

  def index(conn, %{"vault_id" => vault_id}) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "list_documents",
        %{"vault_id" => vault_id},
        index(conn),
        conn.assigns.authorization
      )
    )
  end

  def show(conn, %{"vault_id" => vault_id, "path" => path_segments}) do
    arguments = %{"vault_id" => vault_id, "path" => document_path(path_segments)}

    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call("read_document", arguments, index(conn), conn.assigns.authorization)
    )
  end

  def write(conn, %{
        "vault_id" => vault_id,
        "path" => path_segments,
        "data_base64" => data_base64
      }) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "write_document",
        %{
          "vault_id" => vault_id,
          "path" => document_path(path_segments),
          "data_base64" => data_base64
        },
        index(conn),
        conn.assigns.authorization
      )
    )
  end

  def write(conn, _params),
    do: MarkdowWeb.ApiResponse.send_result(conn, {:error, :invalid_arguments})

  def delete(conn, %{"vault_id" => vault_id, "path" => path_segments}) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "delete_document",
        %{"vault_id" => vault_id, "path" => document_path(path_segments)},
        index(conn),
        conn.assigns.authorization
      )
    )
  end

  defp document_path(path_segments) when is_list(path_segments), do: Enum.join(path_segments, "/")
  defp document_path(path) when is_binary(path), do: path
  defp index(conn), do: conn.private[:markdow_index] || Index.context()
end
