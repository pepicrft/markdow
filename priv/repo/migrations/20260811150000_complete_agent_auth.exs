defmodule Markdow.Repo.Migrations.CompleteAgentAuth do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :hashed_password, :text
      add :signed_up_by_agent, :boolean, null: false, default: false
    end

    alter table(:agent_auth_registrations) do
      add :claimed_by_user_id, references(:users, type: :text, on_delete: :nilify_all)
      add :registration_address, :text
      add :claim_address, :text
      add :confirmed_address, :text
      add :failed_claim_attempts, :integer, null: false, default: 0
    end

    create index(:agent_auth_registrations, [:claimed_by_user_id])
    create index(:agent_auth_registrations, [:registration_address, :created_at])

    alter table(:agent_auth_access_tokens) do
      add :resource, :text
    end
  end
end
