defmodule Markdow.Signups do
  @moduledoc false

  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts \\ []) do
    case Keyword.fetch(opts, :signups_enabled) do
      {:ok, enabled} when is_boolean(enabled) -> enabled
      _missing -> Application.get_env(:markdow, :signups_enabled, true)
    end
  end
end
