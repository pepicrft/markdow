defmodule Markdow.Accounts.Vault do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "vaults" do
    field(:name, :string)
    field(:storage_prefix, :string)

    belongs_to(:user, Markdow.Accounts.User, type: :string)

    timestamps()
  end

  def changeset(vault, attrs) do
    vault
    |> cast(attrs, [:id, :user_id, :name, :storage_prefix])
    |> validate_required([:id, :user_id, :name, :storage_prefix])
    |> validate_format(:id, ~r/^[A-Za-z0-9][A-Za-z0-9._-]*$/)
    |> validate_length(:name, min: 1, max: 120)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:storage_prefix)
  end
end
