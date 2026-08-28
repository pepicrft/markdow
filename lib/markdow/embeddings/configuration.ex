defmodule Markdow.Embeddings.Configuration do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Markdow.Embeddings.EndpointPolicy

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{
          user_id: String.t(),
          endpoint: String.t(),
          model: String.t(),
          dimensions: pos_integer() | nil,
          token_ciphertext: binary(),
          token_iv: binary(),
          token_tag: binary(),
          token_suffix: String.t(),
          validated_at: DateTime.t() | nil,
          connection_target: map() | nil
        }

  schema "user_embedding_configurations" do
    field(:user_id, :string, primary_key: true)
    field(:endpoint, :string)
    field(:model, :string)
    field(:dimensions, :integer)
    field(:token_ciphertext, :binary)
    field(:token_iv, :binary)
    field(:token_tag, :binary)
    field(:token_suffix, :string)
    field(:validated_at, :utc_datetime_usec)
    field(:connection_target, :map, virtual: true)

    timestamps()
  end

  def changeset(configuration, attrs) do
    configuration
    |> cast(attrs, [
      :user_id,
      :endpoint,
      :model,
      :dimensions,
      :token_ciphertext,
      :token_iv,
      :token_tag,
      :token_suffix,
      :validated_at
    ])
    |> validate_required([
      :user_id,
      :endpoint,
      :model,
      :token_ciphertext,
      :token_iv,
      :token_tag,
      :token_suffix
    ])
    |> validate_length(:endpoint, min: 1, max: 500)
    |> validate_length(:model, min: 1, max: 200)
    |> validate_number(:dimensions, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_endpoint()
    |> foreign_key_constraint(:user_id)
  end

  # The address is checked here as well as before each request, so a refused
  # endpoint is reported as a validation error rather than reaching the wire.
  defp validate_endpoint(changeset) do
    validate_change(changeset, :endpoint, fn :endpoint, endpoint ->
      case EndpointPolicy.check(endpoint) do
        {:ok, _uri} -> []
        {:error, reason} -> [endpoint: message(reason)]
      end
    end)
  end

  defp message(:embedding_endpoint_insecure), do: "must use https"

  defp message(:embedding_endpoint_forbidden),
    do: "must not resolve to a private or loopback address"

  defp message(:embedding_endpoint_unresolvable), do: "could not be resolved"
  defp message(_reason), do: "is not a valid endpoint"
end
