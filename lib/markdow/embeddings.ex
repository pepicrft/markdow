defmodule Markdow.Embeddings do
  @moduledoc """
  Manages per-account embedding provider configuration and requests.

  An account brings its own endpoint, model, and credential, so the deployment
  does not choose a provider on anyone's behalf. Every vault an account owns
  embeds through that configuration.

  Writing a configuration performs a real embedding request first and stores
  nothing unless it succeeds, so a saved configuration is one that has been
  seen to work.
  """

  import Ecto.Query

  alias Markdow.Accounts
  alias Markdow.Embeddings.Configuration
  alias Markdow.Embeddings.EndpointPolicy
  alias Markdow.Index.Context
  alias Markdow.Secrets

  @validation_input "Validate this Markdow embedding configuration."
  @maximum_input_bytes 100_000

  @spec get_configuration(Context.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def get_configuration(%Context{} = index, user_id) do
    with {:ok, _user} <- Accounts.get_user(user_id, index.repo),
         %Configuration{} = configuration <- index.repo.get(Configuration, user_id) do
      {:ok, public_configuration(configuration)}
    else
      nil -> {:error, :embedding_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stores a configuration, but only once it has produced an embedding.

  The candidate is assembled and exercised before anything is written, so a
  failing endpoint, model, or credential leaves any previous configuration
  untouched rather than replacing a working one with a broken one.
  """
  @spec put_configuration(Context.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def put_configuration(%Context{} = index, user_id, attrs) when is_map(attrs) do
    existing = index.repo.get(Configuration, user_id)

    supplied = Map.get(attrs, "token")

    with {:ok, _user} <- Accounts.get_user(user_id, index.repo),
         {:ok, token} <- token(existing, index, user_id, supplied),
         {:ok, candidate} <- candidate(user_id, existing, attrs),
         {:ok, secret_attrs} <- secret_attrs(index, user_id, existing, supplied),
         {:ok, _result} <- request(index, candidate, token, @validation_input),
         {:ok, stored} <- store(index, user_id, candidate, secret_attrs, supplied) do
      {:ok, public_configuration(stored)}
    end
  end

  @spec validate_configuration(Context.t(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def validate_configuration(%Context{} = index, user_id, token_override \\ nil) do
    with {:ok, configuration} <- configuration(index, user_id),
         {:ok, token} <- credential(index, configuration, token_override),
         {:ok, result} <- request(index, configuration, token, @validation_input),
         {:ok, updated} <- validated(index, configuration) do
      {:ok,
       %{
         status: "valid",
         user_id: user_id,
         endpoint: updated.endpoint,
         model: result.model,
         dimensions: length(result.embedding)
       }}
    end
  end

  @doc """
  Embeds text for a vault using the configuration of the account that owns it.
  """
  @spec embed(Context.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def embed(index, vault_id, input, token_override \\ nil)

  def embed(%Context{} = index, vault_id, input, token_override)
      when is_binary(input) and byte_size(input) > 0 and byte_size(input) <= @maximum_input_bytes do
    with {:ok, vault} <- Accounts.get_vault(vault_id, index.repo),
         {:ok, configuration} <- configuration(index, vault.user_id),
         {:ok, token} <- credential(index, configuration, token_override),
         {:ok, result} <- request(index, configuration, token, input) do
      {:ok,
       %{
         vault_id: vault_id,
         user_id: vault.user_id,
         endpoint: configuration.endpoint,
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
  def delete_configuration(%Context{} = index, user_id) do
    case index.repo.delete_all(
           from(configuration in Configuration, where: configuration.user_id == ^user_id)
         ) do
      {0, _records} -> {:error, :embedding_not_configured}
      {_count, _records} -> {:ok, %{user_id: user_id, deleted: true}}
    end
  end

  # The address is re-checked here rather than trusting what was stored,
  # because the name in a saved configuration can be repointed at an internal
  # address after it was accepted.
  defp request(index, configuration, token, input) do
    with {:ok, _uri} <- EndpointPolicy.check(configuration.endpoint) do
      index.embedding_client.embed(configuration, token, input)
    end
  end

  defp configuration(index, user_id) do
    case index.repo.get(Configuration, user_id) do
      nil -> {:error, :embedding_not_configured}
      configuration -> {:ok, configuration}
    end
  end

  defp candidate(user_id, existing, attrs) do
    endpoint = Map.get(attrs, "endpoint") || endpoint_of(existing)
    model = Map.get(attrs, "model") || model_of(existing)

    dimensions =
      if Map.has_key?(attrs, "dimensions"),
        do: Map.get(attrs, "dimensions"),
        else: dimensions_of(existing)

    if is_binary(endpoint) and is_binary(model) do
      {:ok,
       %Configuration{
         user_id: user_id,
         endpoint: endpoint,
         model: model,
         dimensions: dimensions
       }}
    else
      {:error, :invalid_arguments}
    end
  end

  defp endpoint_of(%Configuration{endpoint: endpoint}), do: endpoint
  defp endpoint_of(_existing), do: nil

  defp model_of(%Configuration{model: model}), do: model
  defp model_of(_existing), do: nil

  defp dimensions_of(%Configuration{dimensions: dimensions}), do: dimensions
  defp dimensions_of(_existing), do: nil

  # An update that does not carry a new credential must not write the credential
  # columns at all. Writing back the values read at the start would undo a
  # credential another request changed while the provider call was in flight.
  #
  # `returning: true` makes the database supply the stored row, so a caller is
  # told the real creation time rather than the one this insert proposed and the
  # conflict clause discarded.
  defp store(index, user_id, candidate, secret_attrs, supplied) do
    attrs =
      %{
        user_id: user_id,
        endpoint: candidate.endpoint,
        model: candidate.model,
        dimensions: candidate.dimensions,
        validated_at: DateTime.utc_now()
      }
      |> Map.merge(secret_attrs)

    replaced =
      if is_binary(supplied) and supplied != "" do
        [
          :endpoint,
          :model,
          :dimensions,
          :token_ciphertext,
          :token_iv,
          :token_tag,
          :token_suffix,
          :validated_at,
          :updated_at
        ]
      else
        [:endpoint, :model, :dimensions, :validated_at, :updated_at]
      end

    %Configuration{user_id: user_id}
    |> Configuration.changeset(attrs)
    |> index.repo.insert(
      conflict_target: :user_id,
      on_conflict: {:replace, replaced},
      returning: true
    )
  end

  defp token(existing, index, user_id, supplied)

  defp token(_existing, _index, _user_id, supplied)
       when is_binary(supplied) and byte_size(supplied) > 0,
       do: {:ok, supplied}

  defp token(%Configuration{} = existing, index, user_id, nil),
    do: Secrets.decrypt(existing, index.embedding_secret_key, user_id)

  defp token(_existing, _index, _user_id, _supplied), do: {:error, :invalid_arguments}

  defp secret_attrs(index, user_id, _existing, token)
       when is_binary(token) and byte_size(token) > 0 do
    with {:ok, encrypted} <- Secrets.encrypt(token, index.embedding_secret_key, user_id) do
      {:ok, Map.put(encrypted, :token_suffix, token_suffix(token))}
    end
  end

  defp secret_attrs(_index, _user_id, %Configuration{} = existing, nil) do
    {:ok,
     Map.take(existing, [
       :token_ciphertext,
       :token_iv,
       :token_tag,
       :token_suffix
     ])}
  end

  defp secret_attrs(_index, _user_id, _existing, _token), do: {:error, :invalid_arguments}

  defp credential(_index, _configuration, token) when is_binary(token) and byte_size(token) > 0,
    do: {:ok, token}

  defp credential(index, configuration, nil),
    do: Secrets.decrypt(configuration, index.embedding_secret_key, configuration.user_id)

  defp credential(_index, _configuration, _token), do: {:error, :invalid_arguments}

  defp validated(index, configuration) do
    configuration
    |> Ecto.Changeset.change(validated_at: DateTime.utc_now())
    |> index.repo.update()
  end

  defp public_configuration(configuration) do
    %{
      user_id: configuration.user_id,
      endpoint: configuration.endpoint,
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
