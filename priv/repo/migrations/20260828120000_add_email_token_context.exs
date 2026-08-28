defmodule Markdow.Repo.Migrations.AddEmailTokenContext do
  use Ecto.Migration

  def change do
    alter table(:user_email_verification_tokens) do
      add :context, :text, null: false, default: "verification"
    end

    create index(:user_email_verification_tokens, [:user_id, :context])

  end
end
