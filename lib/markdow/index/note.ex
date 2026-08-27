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
    |> cast(attrs, [:vault_id, :id, :title, :path, :body, :metadata], empty_values: [])
    |> validate_required([:vault_id, :id, :title, :path, :metadata])
    |> validate_body()
    |> unique_constraint([:vault_id, :path])
  end

  # An empty note is a real note: Obsidian writes one every time somebody creates
  # a page and does not type in it yet, and a vault carries them by the dozen.
  # `validate_required/3` counts "" and whitespace as missing, so the body is
  # checked for presence rather than for content, and `cast/4` keeps the bytes it
  # would otherwise discard as empty.
  defp validate_body(changeset) do
    if is_binary(get_field(changeset, :body)),
      do: changeset,
      else: add_error(changeset, :body, "can't be blank", validation: :required)
  end
end
