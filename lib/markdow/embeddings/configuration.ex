defmodule Markdow.Embeddings.Configuration do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{
          vault_id: String.t(),
          provider: String.t(),
          model: String.t(),
          dimensions: pos_integer() | nil,
          token_ciphertext: binary(),
          token_iv: binary(),
          token_tag: binary(),
          token_suffix: String.t(),
          validated_at: DateTime.t() | nil
        }

  schema "embedding_configurations" do
    field(:vault_id, :string, primary_key: true)
    field(:provider, :string)
    field(:model, :string)
    field(:dimensions, :integer)
    field(:token_ciphertext, :binary)
    field(:token_iv, :binary)
    field(:token_tag, :binary)
    field(:token_suffix, :string)
    field(:validated_at, :utc_datetime_usec)

    timestamps()
  end

  def changeset(configuration, attrs) do
    configuration
    |> cast(attrs, [
      :vault_id,
      :provider,
      :model,
      :dimensions,
      :token_ciphertext,
      :token_iv,
      :token_tag,
      :token_suffix,
      :validated_at
    ])
    |> validate_required([
      :vault_id,
      :provider,
      :model,
      :token_ciphertext,
      :token_iv,
      :token_tag,
      :token_suffix
    ])
    |> validate_inclusion(:provider, ["openai"])
    |> validate_length(:model, min: 1, max: 120)
    |> validate_number(:dimensions, greater_than: 0, less_than_or_equal_to: 10_000)
    |> foreign_key_constraint(:vault_id)
  end
end
