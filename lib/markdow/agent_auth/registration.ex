defmodule Markdow.AgentAuth.Registration do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}

  schema "agent_auth_registrations" do
    field(:registration_type, :string)
    field(:status, :string)
    field(:claim_email, :string)
    field(:claim_token_hash, :binary)
    field(:claim_attempt_token_hash, :binary)
    field(:user_code_hash, :binary)
    field(:created_at, :integer)
    field(:expires_at, :integer)
    field(:claim_attempt_expires_at, :integer)
    field(:claimed_at, :integer)
    field(:last_polled_at, :integer)
    field(:claimed_by_user_id, :string)
    field(:registration_address, :string)
    field(:claim_address, :string)
    field(:confirmed_address, :string)
    field(:failed_claim_attempts, :integer, default: 0)
    field(:failed_sign_in_attempts, :integer, default: 0)
    field(:email_verified, :boolean, default: false)
  end
end
