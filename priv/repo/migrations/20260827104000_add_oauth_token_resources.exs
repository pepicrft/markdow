defmodule Markdow.Repo.Migrations.AddOauthTokenResources do
  use Ecto.Migration

  # RFC 8707 resource indicators, which the Model Context Protocol requires a
  # server to honour so a token minted for one interface is not accepted at
  # another. Boruta has no column for the audience of a token, and Markdow's own
  # access tokens already carry one, so the binding is recorded alongside.
  #
  # Keyed by digest rather than by the token itself, matching how
  # agent_auth_access_tokens stores its tokens.
  def change do
    create table(:oauth_token_resources, primary_key: false) do
      add :token_digest, :binary, primary_key: true
      add :resource, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end
  end
end
