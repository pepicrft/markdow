defmodule MarkdowWeb.UserController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.Index
  alias Markdow.Operations
  alias MarkdowWeb.ApiSchemas.{User, UserInput}
  alias OpenApiSpex.Schema

  tags ["Users"]
  security [%{"bearerAuth" => []}]

  plug MarkdowWeb.ApiAuth, [scopes: ["users:read"]] when action in [:index, :show]

  plug MarkdowWeb.ApiAuth,
       [scopes: ["users:write"]]
       when action in [:create, :revoke_agent_credentials]

  operation :index,
    operation_id: "list_users",
    summary: "List users",
    responses: [
      ok: {"Users", "application/json", %Schema{type: :array, items: User}}
    ]

  operation :show,
    operation_id: "get_user",
    summary: "Get a user",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [ok: {"User", "application/json", User}]

  operation :create,
    operation_id: "create_user",
    summary: "Create a user",
    request_body: {"User", "application/json", UserInput},
    responses: [created: {"Created user", "application/json", User}]

  operation :revoke_agent_credentials,
    operation_id: "revoke_agent_credentials",
    summary: "Revoke every agent credential for a user",
    parameters: [user_id: [in: :path, type: :string, required: true]],
    responses: [
      ok:
        {"Revocation result", "application/json",
         %Schema{
           type: :object,
           properties: %{
             user_id: %Schema{type: :string},
             revoked: %Schema{type: :integer}
           },
           required: [:user_id, :revoked]
         }}
    ]

  def index(conn, _params) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call("list_users", %{}, index(conn), conn.assigns.authorization)
    )
  end

  def show(conn, %{"id" => id}) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call("get_user", %{"id" => id}, index(conn), conn.assigns.authorization)
    )
  end

  def create(conn, params) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call("create_user", params, index(conn), conn.assigns.authorization),
      201
    )
  end

  def revoke_agent_credentials(conn, %{"user_id" => user_id}) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(
        "revoke_agent_credentials",
        %{"user_id" => user_id},
        index(conn),
        conn.assigns.authorization
      )
    )
  end

  defp index(conn), do: conn.private[:markdow_index] || Index.context()
end
