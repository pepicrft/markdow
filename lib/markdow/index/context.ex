defmodule Markdow.Index.Context do
  @moduledoc false

  @enforce_keys [:repo, :storage]
  defstruct [
    :repo,
    :storage,
    :embedding_client,
    :embedding_secret_key,
    :email_notifier,
    :signups_enabled
  ]

  @type t :: %__MODULE__{
          repo: module(),
          storage: Markdow.Storage.storage_reference(),
          embedding_client: module(),
          embedding_secret_key: binary() | nil,
          email_notifier: module(),
          signups_enabled: boolean()
        }
end
