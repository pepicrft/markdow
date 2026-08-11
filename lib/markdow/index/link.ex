defmodule Markdow.Index.Link do
  @moduledoc false

  use Ecto.Schema

  @primary_key false

  schema "links" do
    field(:vault_id, :string, primary_key: true)
    field(:source_id, :string, primary_key: true)
    field(:target_id, :string, primary_key: true)
    field(:context, :string)
  end
end
