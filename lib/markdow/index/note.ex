defmodule Markdow.Index.Note do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  schema "notes" do
    field(:vault_id, :string, primary_key: true)
    field(:id, :string, primary_key: true)
    field(:title, :string)
    field(:path, :string)
    field(:body, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:vault_id, :id, :title, :path, :body, :metadata])
    |> validate_required([:vault_id, :id, :title, :path, :body, :metadata])
    |> unique_constraint([:vault_id, :path])
  end
end
