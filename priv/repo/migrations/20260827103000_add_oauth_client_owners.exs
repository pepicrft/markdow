defmodule Markdow.Repo.Migrations.AddOauthClientOwners do
  use Ecto.Migration

  # Boruta owns oauth_clients, and its registration changeset casts a fixed list
  # of RFC 7591 attributes that does not include metadata. The account a client
  # acts for is Markdow's concern rather than Boruta's, so it is recorded here
  # instead of being smuggled into a column Boruta controls.
  #
  # Without a row here a client has no account, and Operations.authorize_arguments/4
  # refuses every user and vault scoped call. That is the safe direction: an
  # unowned client can be issued a token and still reach nothing.
  def change do
    create table(:oauth_client_owners, primary_key: false) do
      add :client_id, references(:oauth_clients, type: :uuid, on_delete: :delete_all),
        primary_key: true

      add :user_id, references(:users, type: :text, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:oauth_client_owners, [:user_id])
  end
end
