defmodule Markdow.OAuth.TokenResource do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "oauth_token_resources" do
    field(:token_digest, :binary, primary_key: true)
    field(:resource, :string)

    timestamps()
  end

  def changeset(token_resource, attrs) do
    token_resource
    |> cast(attrs, [:token_digest, :resource])
    |> validate_required([:token_digest, :resource])
    |> unique_constraint(:token_digest, name: :oauth_token_resources_pkey)
  end
end
