defmodule Markdow.OAuth.ClientOwner do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  schema "oauth_client_owners" do
    field(:client_id, Ecto.UUID, primary_key: true)
    field(:user_id, :string)

    timestamps()
  end

  def changeset(owner, attrs) do
    owner
    |> cast(attrs, [:client_id, :user_id])
    |> validate_required([:client_id, :user_id])
    |> unique_constraint(:client_id, name: :oauth_client_owners_pkey)
    |> foreign_key_constraint(:client_id)
    |> foreign_key_constraint(:user_id)
  end
end
