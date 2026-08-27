defmodule MarkdowWeb.OAuthClientController do
  @moduledoc """
  Seeing and removing the clients registered for an account.

  A registered client's secret never expires, so deleting the client is the only
  revocation it has. Without somewhere to do that, a leaked secret would be
  permanent, and an account holder would have no way to find out what is holding
  access to their vaults.

  Secrets are never listed. They are shown once, at registration.
  """

  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.OAuth
  alias OpenApiSpex.Schema

  plug MarkdowWeb.ApiAuth, [scopes: ["users:read"]] when action in [:index]
  plug MarkdowWeb.ApiAuth, [scopes: ["users:write"]] when action in [:delete]

  tags ["Agent authentication"]
  security [%{"bearerAuth" => []}]

  operation :index,
    operation_id: "list_oauth_clients",
    summary: "List the OAuth clients registered for an account",
    parameters: [user_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Clients", "application/json", %Schema{type: :array, items: %Schema{type: :object}}}
    ]

  operation :delete,
    operation_id: "delete_oauth_client",
    summary: "Delete an OAuth client and revoke its tokens",
    parameters: [
      user_id: [in: :path, type: :string, required: true],
      id: [in: :path, type: :string, required: true]
    ],
    responses: [ok: {"Deleted client", "application/json", %Schema{type: :object}}]

  def index(conn, %{"user_id" => user_id}) do
    case authorize(conn, user_id) do
      :ok -> json(conn, OAuth.list_clients(user_id))
      {:error, reason} -> MarkdowWeb.ApiResponse.send_result(conn, {:error, reason})
    end
  end

  def delete(conn, %{"user_id" => user_id, "id" => client_id}) do
    with :ok <- authorize(conn, user_id),
         :ok <- OAuth.delete_client(client_id, user_id) do
      json(conn, %{client_id: client_id, deleted: true})
    else
      {:error, reason} -> MarkdowWeb.ApiResponse.send_result(conn, {:error, reason})
    end
  end

  # Deleting a client is how access is taken away, so a client must not be able
  # to delete its siblings or itself out from under the person who made it. The
  # `users:write` scope this action requires is already withheld from every
  # agent and registered client, which leaves the application key and the
  # account holder.
  defp authorize(conn, user_id) do
    case conn.assigns.authorization do
      %{kind: :api_key} -> :ok
      %{kind: :access_token, user_id: ^user_id} -> :ok
      _other -> {:error, :forbidden}
    end
  end
end
