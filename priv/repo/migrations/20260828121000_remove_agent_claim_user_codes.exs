defmodule Markdow.Repo.Migrations.RemoveAgentClaimUserCodes do
  use Ecto.Migration

  def change do
    alter table(:agent_auth_registrations) do
      remove :user_code_hash
    end
  end
end
