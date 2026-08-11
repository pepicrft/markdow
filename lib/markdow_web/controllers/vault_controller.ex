defmodule MarkdowWeb.VaultController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.Index
  alias Markdow.Operations
  alias MarkdowWeb.ApiSchemas.{Vault, VaultInput}
  alias OpenApiSpex.Schema

  tags ["Vaults"]
  security [%{"bearerAuth" => []}]

  plug MarkdowWeb.ApiAuth, [scopes: ["vaults:read"]] when action in [:index, :show]
  plug MarkdowWeb.ApiAuth, [scopes: ["vaults:write"]] when action == :create

  operation :index,
    operation_id: "list_vaults",
    summary: "List a user's vaults",
    parameters: [user_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Vaults", "application/json", %Schema{type: :array, items: Vault}}
    ]

  operation :show,
    operation_id: "get_vault",
    summary: "Get a vault",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Vault", "application/json", Vault}]

  operation :create,
    operation_id: "create_vault",
    summary: "Create a vault",
    parameters: [user_id: [in: :path, type: :string, required: true]],
    request_body: {"Vault", "application/json", VaultInput},
    responses: [created: {"Created vault", "application/json", Vault}]

  def index(conn, %{"user_id" => user_id}) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "list_vaults",
        %{"user_id" => user_id},
        index(conn),
        conn.assigns.authorization
      )
    )
  end

  def show(conn, %{"id" => id}) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call("get_vault", %{"id" => id}, index(conn), conn.assigns.authorization)
    )
  end

  def create(conn, %{"user_id" => user_id} = params) do
    arguments = params |> Map.delete("user_id") |> Map.put("user_id", user_id)

    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call("create_vault", arguments, index(conn), conn.assigns.authorization),
      201
    )
  end

  defp index(conn), do: conn.private[:markdow_index] || Index.context()
end
