defmodule Markdow.Embeddings do
  @moduledoc "Manages per-vault embedding provider configuration and requests."

  import Ecto.Query

  alias Markdow.Accounts
  alias Markdow.Embeddings.Configuration
  alias Markdow.Index.Context
  alias Markdow.Secrets

  @validation_input "Validate this Markdow embedding configuration."
  @maximum_input_bytes 100_000

  @spec get_configuration(Context.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def get_configuration(%Context{} = index, vault_id) do
    with {:ok, _vault} <- Accounts.get_vault(vault_id, index.repo),
         %Configuration{} = configuration <- index.repo.get(Configuration, vault_id) do
      {:ok, public_configuration(configuration)}
    else
      nil -> {:error, :embedding_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec put_configuration(Context.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def put_configuration(%Context{} = index, vault_id, attrs) when is_map(attrs) do
    with {:ok, _vault} <- Accounts.get_vault(vault_id, index.repo),
         existing = index.repo.get(Configuration, vault_id),
         {:ok, secret_attrs} <- secret_attrs(index, vault_id, existing, Map.get(attrs, "token")) do
      configuration_attrs = %{
        vault_id: vault_id,
        provider: Map.get(attrs, "provider", "openai"),
        model: Map.get(attrs, "model", "text-embedding-3-small"),
        dimensions: Map.get(attrs, "dimensions"),
        validated_at: nil
      }

      %Configuration{vault_id: vault_id}
      |> Configuration.changeset(Map.merge(configuration_attrs, secret_attrs))
      |> index.repo.insert(
        conflict_target: :vault_id,
        on_conflict:
          {:replace,
           [
             :provider,
             :model,
             :dimensions,
             :token_ciphertext,
             :token_iv,
             :token_tag,
             :token_suffix,
             :validated_at,
             :updated_at
           ]}
      )
      |> map_configuration()
    end
  end

  @spec validate_configuration(Context.t(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def validate_configuration(%Context{} = index, vault_id, token_override \\ nil) do
    with {:ok, configuration} <- configuration(index, vault_id),
         {:ok, token} <- credential(index, configuration, token_override),
         {:ok, result} <- index.embedding_client.embed(configuration, token, @validation_input),
         {:ok, updated} <- validated(index, configuration) do
      {:ok,
       %{
         status: "valid",
         vault_id: vault_id,
         provider: updated.provider,
         model: result.model,
         dimensions: length(result.embedding)
       }}
    end
  end

  @spec embed(Context.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def embed(index, vault_id, input, token_override \\ nil)

  def embed(%Context{} = index, vault_id, input, token_override)
      when is_binary(input) and byte_size(input) > 0 and byte_size(input) <= @maximum_input_bytes do
    with {:ok, configuration} <- configuration(index, vault_id),
         {:ok, token} <- credential(index, configuration, token_override),
         {:ok, result} <- index.embedding_client.embed(configuration, token, input) do
      {:ok,
       %{
         vault_id: vault_id,
         provider: configuration.provider,
         model: result.model,
         embedding: result.embedding,
         dimensions: length(result.embedding),
         usage: result.usage
       }}
    end
  end

  def embed(%Context{}, _vault_id, _input, _token_override),
    do: {:error, :invalid_embedding_input}

  @spec delete_configuration(Context.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def delete_configuration(%Context{} = index, vault_id) do
    case index.repo.delete_all(
           from(configuration in Configuration, where: configuration.vault_id == ^vault_id)
         ) do
      {0, _records} -> {:error, :embedding_not_configured}
      {_count, _records} -> {:ok, %{vault_id: vault_id, deleted: true}}
    end
  end

  defp configuration(index, vault_id) do
    with {:ok, _vault} <- Accounts.get_vault(vault_id, index.repo) do
      case index.repo.get(Configuration, vault_id) do
        nil -> {:error, :embedding_not_configured}
        configuration -> {:ok, configuration}
      end
    end
  end

  defp secret_attrs(index, vault_id, nil, token) when is_binary(token) and byte_size(token) > 0 do
    with {:ok, encrypted} <- Secrets.encrypt(token, index.embedding_secret_key, vault_id) do
      {:ok, Map.put(encrypted, :token_suffix, token_suffix(token))}
    end
  end

  defp secret_attrs(_index, _vault_id, %Configuration{} = existing, nil) do
    {:ok,
     Map.take(existing, [
       :token_ciphertext,
       :token_iv,
       :token_tag,
       :token_suffix
     ])}
  end

  defp secret_attrs(_index, _vault_id, _existing, _token), do: {:error, :invalid_arguments}

  defp credential(_index, _configuration, token) when is_binary(token) and byte_size(token) > 0,
    do: {:ok, token}

  defp credential(index, configuration, nil),
    do: Secrets.decrypt(configuration, index.embedding_secret_key, configuration.vault_id)

  defp credential(_index, _configuration, _token), do: {:error, :invalid_arguments}

  defp validated(index, configuration) do
    configuration
    |> Ecto.Changeset.change(validated_at: DateTime.utc_now())
    |> index.repo.update()
  end

  defp map_configuration({:ok, configuration}), do: {:ok, public_configuration(configuration)}
  defp map_configuration({:error, reason}), do: {:error, reason}

  defp public_configuration(configuration) do
    %{
      vault_id: configuration.vault_id,
      provider: configuration.provider,
      model: configuration.model,
      dimensions: configuration.dimensions,
      credential_hint: "••••#{configuration.token_suffix}",
      validated_at: configuration.validated_at,
      created_at: configuration.inserted_at,
      updated_at: configuration.updated_at
    }
  end

  defp token_suffix(token) do
    length = String.length(token)
    String.slice(token, max(length - 4, 0), 4)
  end
end
