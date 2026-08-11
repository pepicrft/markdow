defmodule Markdow.Repo.Migrations.AddUsersAndVaults do
  use Ecto.Migration

  def up do
    create table(:users, primary_key: false) do
      add :id, :text, primary_key: true
      add :email, :text, null: false
      add :name, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])

    create table(:vaults, primary_key: false) do
      add :id, :text, primary_key: true
      add :user_id, references(:users, type: :text, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :storage_prefix, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:vaults, [:user_id])
    create unique_index(:vaults, [:storage_prefix])

    execute("""
    INSERT INTO users (id, email, name, inserted_at, updated_at)
    VALUES ('local', 'owner@markdow.local', 'Local owner', NOW(), NOW())
    """)

    execute("""
    INSERT INTO vaults (id, user_id, name, storage_prefix, inserted_at, updated_at)
    VALUES ('default', 'local', 'Default vault', '', NOW(), NOW())
    """)

    execute("ALTER TABLE links DROP CONSTRAINT IF EXISTS links_source_id_fkey")
    execute("ALTER TABLE links DROP CONSTRAINT IF EXISTS links_target_id_fkey")
    execute("ALTER TABLE tags DROP CONSTRAINT IF EXISTS tags_note_id_fkey")

    alter table(:notes) do
      add :vault_id, references(:vaults, type: :text, on_delete: :delete_all),
        null: false,
        default: "default"
    end

    alter table(:links) do
      add :vault_id, :text, null: false, default: "default"
    end

    alter table(:tags) do
      add :vault_id, :text, null: false, default: "default"
    end

    drop index(:notes, [:path])

    execute("ALTER TABLE notes DROP CONSTRAINT notes_pkey")
    execute("ALTER TABLE notes ADD PRIMARY KEY (vault_id, id)")
    create unique_index(:notes, [:vault_id, :path])

    execute("ALTER TABLE links DROP CONSTRAINT links_pkey")
    execute("ALTER TABLE links ADD PRIMARY KEY (vault_id, source_id, target_id)")

    execute("""
    ALTER TABLE links
    ADD CONSTRAINT links_source_note_fkey
    FOREIGN KEY (vault_id, source_id) REFERENCES notes(vault_id, id) ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE links
    ADD CONSTRAINT links_target_note_fkey
    FOREIGN KEY (vault_id, target_id) REFERENCES notes(vault_id, id) ON DELETE CASCADE
    """)

    execute("ALTER TABLE tags DROP CONSTRAINT tags_pkey")
    execute("ALTER TABLE tags ADD PRIMARY KEY (vault_id, note_id, tag)")

    execute("""
    ALTER TABLE tags
    ADD CONSTRAINT tags_note_fkey
    FOREIGN KEY (vault_id, note_id) REFERENCES notes(vault_id, id) ON DELETE CASCADE
    """)

    create index(:links, [:vault_id, :target_id])
    create index(:tags, [:vault_id, :tag])
  end

  def down do
    execute("DELETE FROM notes WHERE vault_id <> 'default'")
    execute("ALTER TABLE links DROP CONSTRAINT links_source_note_fkey")
    execute("ALTER TABLE links DROP CONSTRAINT links_target_note_fkey")
    execute("ALTER TABLE tags DROP CONSTRAINT tags_note_fkey")
    execute("ALTER TABLE links DROP CONSTRAINT links_pkey")
    execute("ALTER TABLE tags DROP CONSTRAINT tags_pkey")
    execute("ALTER TABLE notes DROP CONSTRAINT notes_pkey")
    drop index(:notes, [:vault_id, :path])
    execute("ALTER TABLE notes ADD PRIMARY KEY (id)")
    create unique_index(:notes, [:path])
    execute("ALTER TABLE links ADD PRIMARY KEY (source_id, target_id)")
    execute("ALTER TABLE tags ADD PRIMARY KEY (note_id, tag)")

    alter table(:tags), do: remove(:vault_id)
    alter table(:links), do: remove(:vault_id)
    alter table(:notes), do: remove(:vault_id)

    execute("ALTER TABLE links ADD FOREIGN KEY (source_id) REFERENCES notes(id) ON DELETE CASCADE")
    execute("ALTER TABLE links ADD FOREIGN KEY (target_id) REFERENCES notes(id) ON DELETE CASCADE")
    execute("ALTER TABLE tags ADD FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE")

    drop table(:vaults)
    drop table(:users)
  end
end
