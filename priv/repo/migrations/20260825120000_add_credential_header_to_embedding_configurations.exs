defmodule Markdow.Repo.Migrations.AddCredentialHeaderToEmbeddingConfigurations do
  use Ecto.Migration

  # Not every endpoint speaking the OpenAI embeddings protocol reads the
  # credential from `authorization`. A gateway sitting in front of several
  # providers keeps that header for the caller's own identity and takes its key
  # from a header of its own, so the account records which header carries it.
  #
  # Null keeps the existing behaviour, which is why the column has no default:
  # rows written before this migration mean the same thing as rows written after
  # it that leave the header unset.
  def change do
    alter table(:user_embedding_configurations) do
      add :credential_header, :text
    end
  end
end
