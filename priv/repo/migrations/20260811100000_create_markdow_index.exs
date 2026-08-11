defmodule Markdow.Repo.Migrations.CreateMarkdowIndex do
  use Ecto.Migration

  def change do
    create table(:notes, primary_key: false) do
      add :id, :text, primary_key: true
      add :title, :text, null: false
      add :path, :text, null: false
      add :body, :text, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:notes, [:path])

    execute(
      """
      ALTER TABLE notes
      ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (
        to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(body, ''))
      ) STORED
      """,
      "ALTER TABLE notes DROP COLUMN search_vector"
    )

    execute(
      "CREATE INDEX notes_search_vector_index ON notes USING GIN (search_vector)",
      "DROP INDEX notes_search_vector_index"
    )

    create table(:links, primary_key: false) do
      add :source_id, references(:notes, type: :text, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :target_id, references(:notes, type: :text, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :context, :text
    end

    create index(:links, [:target_id])

    create table(:tags, primary_key: false) do
      add :note_id, references(:notes, type: :text, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :tag, :text, primary_key: true, null: false
    end

    create index(:tags, [:tag])

    create table(:agent_auth_registrations, primary_key: false) do
      add :id, :text, primary_key: true
      add :registration_type, :text, null: false
      add :status, :text, null: false
      add :claim_email, :text, null: false
      add :claim_token_hash, :binary, null: false
      add :claim_attempt_token_hash, :binary, null: false
      add :user_code_hash, :binary, null: false
      add :created_at, :bigint, null: false
      add :expires_at, :bigint, null: false
      add :claim_attempt_expires_at, :bigint, null: false
      add :claimed_at, :bigint
      add :last_polled_at, :bigint
    end

    create unique_index(:agent_auth_registrations, [:claim_token_hash])
    create unique_index(:agent_auth_registrations, [:claim_attempt_token_hash])
    create index(:agent_auth_registrations, [:status, :expires_at])

    create table(:agent_auth_access_tokens, primary_key: false) do
      add :token_hash, :binary, primary_key: true

      add :registration_id,
          references(:agent_auth_registrations, type: :text, on_delete: :delete_all),
          null: false

      add :scopes, :text, null: false
      add :created_at, :bigint, null: false
      add :expires_at, :bigint, null: false
      add :revoked_at, :bigint
    end

    create index(:agent_auth_access_tokens, [:registration_id])

    create table(:agent_auth_events) do
      add :registration_id,
          references(:agent_auth_registrations, type: :text, on_delete: :delete_all),
          null: false

      add :name, :text, null: false
      add :metadata, :map, null: false, default: %{}
      add :created_at, :bigint, null: false
    end

    create index(:agent_auth_events, [:registration_id, :created_at])
  end
end
