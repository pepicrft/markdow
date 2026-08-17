defmodule MarkdowWeb.EmbeddingController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.Index
  alias Markdow.Operations

  alias MarkdowWeb.ApiSchemas.{
    DeletedEmbeddingConfiguration,
    EmbeddingConfiguration,
    EmbeddingConfigurationInput,
    EmbeddingInput,
    EmbeddingResult,
    EmbeddingValidation,
    EmbeddingValidationInput
  }

  tags ["Embeddings"]
  security [%{"bearerAuth" => []}]

  plug MarkdowWeb.ApiAuth, [scopes: ["embeddings:read"]] when action == :show
  plug MarkdowWeb.ApiAuth, [scopes: ["embeddings:write"]] when action != :show

  operation :show,
    operation_id: "get_embedding_configuration",
    summary: "Get a redacted embedding configuration",
    parameters: [user_id: [in: :path, type: :string, required: true]],
    responses: [ok: {"Embedding configuration", "application/json", EmbeddingConfiguration}]

  operation :update,
    operation_id: "configure_embedding",
    summary: "Configure embeddings with an account-supplied endpoint and credential",
    parameters: [user_id: [in: :path, type: :string, required: true]],
    request_body: {"Embedding configuration", "application/json", EmbeddingConfigurationInput},
    responses: [ok: {"Embedding configuration", "application/json", EmbeddingConfiguration}]

  operation :validate,
    operation_id: "validate_embedding_configuration",
    summary: "Validate an embedding configuration",
    parameters: [user_id: [in: :path, type: :string, required: true]],
    request_body: {"Optional temporary credential", "application/json", EmbeddingValidationInput},
    responses: [ok: {"Validation result", "application/json", EmbeddingValidation}]

  operation :embed,
    operation_id: "embed_text",
    summary: "Create an embedding with a user-supplied credential",
    parameters: [vault_id: [in: :path, type: :string, required: true]],
    request_body: {"Text to embed", "application/json", EmbeddingInput},
    responses: [ok: {"Embedding", "application/json", EmbeddingResult}]

  operation :delete,
    operation_id: "delete_embedding_configuration",
    summary: "Delete an embedding configuration",
    parameters: [user_id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Deleted embedding configuration", "application/json", DeletedEmbeddingConfiguration}
    ]

  def show(conn, %{"user_id" => user_id}),
    do: call(conn, "get_embedding_configuration", %{"user_id" => user_id})

  def update(conn, %{"user_id" => user_id} = params),
    do: call(conn, "configure_embedding", Map.put(params, "user_id", user_id))

  def validate(conn, %{"user_id" => user_id} = params),
    do: call(conn, "validate_embedding_configuration", Map.put(params, "user_id", user_id))

  # Embedding stays addressed by vault, since the text belongs to one. The
  # configuration used is the one owned by the account that owns the vault.
  def embed(conn, %{"vault_id" => vault_id} = params),
    do: call(conn, "embed_text", Map.put(params, "vault_id", vault_id))

  def delete(conn, %{"user_id" => user_id}),
    do: call(conn, "delete_embedding_configuration", %{"user_id" => user_id})

  defp call(conn, operation, arguments) do
    MarkdowWeb.ApiResponse.send_result(
      conn,
      Operations.call(operation, arguments, index(conn), conn.assigns.authorization)
    )
  end

  defp index(conn), do: conn.private[:markdow_index] || Index.context()
end
