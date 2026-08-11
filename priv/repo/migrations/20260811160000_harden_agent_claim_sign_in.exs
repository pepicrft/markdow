defmodule Markdow.Repo.Migrations.HardenAgentClaimSignIn do
  use Ecto.Migration

  def change do
    alter table(:agent_auth_registrations) do
      add :failed_sign_in_attempts, :integer, null: false, default: 0
    end
  end
end
