defmodule Markdow.Repo.Migrations.VerifyUserEmails do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :email_verified_at, :utc_datetime_usec
    end

    create table(:user_email_verification_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :text, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :sent_to, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:user_email_verification_tokens, [:token_hash])
    create index(:user_email_verification_tokens, [:user_id])

    alter table(:agent_auth_registrations) do
      add :email_verified, :boolean, null: false, default: false
    end
  end
end
