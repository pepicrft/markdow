defmodule Markdow.AgentAuth.AccessToken do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:token_hash, :binary, autogenerate: false}

  schema "agent_auth_access_tokens" do
    field(:registration_id, :string)
    field(:scopes, :string)
    field(:created_at, :integer)
    field(:expires_at, :integer)
    field(:revoked_at, :integer)
    field(:resource, :string)
  end
end
