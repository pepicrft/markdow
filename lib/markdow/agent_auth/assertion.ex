defmodule Markdow.AgentAuth.Assertion do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:jti_hash, :binary, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "agent_auth_used_assertions" do
    field(:expires_at, :integer)

    timestamps()
  end
end
