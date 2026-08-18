defmodule Markdow.Repo.Migrations.MoveEmbeddingConfigurationsToUsers do
  use Ecto.Migration

  # Embedding configuration belonged to a vault, which meant a person with
  # several vaults supplied the same credential repeatedly. It now belongs to
  # the account, and carries the endpoint so each account chooses its own
  # provider rather than using one the deployment picked.
  def up do
    create table(:user_embedding_configurations, primary_key: false) do
      add :user_id, references(:users, type: :text, on_delete: :delete_all), primary_key: true
      add :endpoint, :text, null: false
      add :model, :text, null: false
      add :dimensions, :integer
      add :token_ciphertext, :binary, null: false
      add :token_iv, :binary, null: false
      add :token_tag, :binary, null: false
      add :token_suffix, :text, null: false
      add :validated_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # The rows are not carried over. A credential is encrypted with its vault
    # identifier as associated data, so it cannot be re-associated with an
    # account without the plain text, and the endpoint the account wants is not
    # recorded anywhere. Affected accounts configure once more.
    drop table(:embedding_configurations)
  end

  def down do
    create table(:embedding_configurations, primary_key: false) do
      add :vault_id, references(:vaults, type: :text, on_delete: :delete_all), primary_key: true
      add :provider, :text, null: false
      add :model, :text, null: false
      add :dimensions, :integer
      add :token_ciphertext, :binary, null: false
      add :token_iv, :binary, null: false
      add :token_tag, :binary, null: false
      add :token_suffix, :text, null: false
      add :validated_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    drop table(:user_embedding_configurations)
  end
end
