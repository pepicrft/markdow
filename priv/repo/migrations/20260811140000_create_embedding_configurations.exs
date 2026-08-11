defmodule Markdow.Repo.Migrations.CreateEmbeddingConfigurations do
  use Ecto.Migration

  def change do
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
  end
end
