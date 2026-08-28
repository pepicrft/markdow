defmodule Markdow.Repo.Migrations.ConsumeAgentIdentityAssertions do
  use Ecto.Migration

  def change do
    create table(:agent_auth_used_assertions, primary_key: false) do
      add(:jti_hash, :binary, primary_key: true)
      add(:expires_at, :bigint, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:agent_auth_used_assertions, [:expires_at]))
  end
end
