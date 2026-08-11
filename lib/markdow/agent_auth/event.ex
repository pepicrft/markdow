defmodule Markdow.AgentAuth.Event do
  @moduledoc false

  use Ecto.Schema

  schema "agent_auth_events" do
    field(:registration_id, :string)
    field(:name, :string)
    field(:metadata, :map, default: %{})
    field(:created_at, :integer)
  end
end
