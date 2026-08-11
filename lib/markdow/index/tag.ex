defmodule Markdow.Index.Tag do
  @moduledoc false

  use Ecto.Schema

  @primary_key false

  schema "tags" do
    field(:vault_id, :string, primary_key: true)
    field(:note_id, :string, primary_key: true)
    field(:tag, :string, primary_key: true)
  end
end
