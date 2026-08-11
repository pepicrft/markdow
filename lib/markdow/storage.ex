defmodule Markdow.Storage do
  @moduledoc """
  The content storage contract.

  PostgreSQL remains the searchable index. A storage implementation owns the
  original Markdown and asset bytes.
  """

  @type id :: String.t()
  @type path :: String.t()

  @callback read_note(id()) :: {:ok, String.t()} | {:error, term()}
  @callback write_note(id(), String.t()) :: :ok | {:error, term()}
  @callback delete_note(id()) :: :ok | {:error, term()}
  @callback list_notes() :: {:ok, [id()]} | {:error, term()}
  @callback read_asset(path()) :: {:ok, binary()} | {:error, term()}
  @callback write_asset(path(), binary()) :: :ok | {:error, term()}
  @callback delete_asset(path()) :: :ok | {:error, term()}
  @callback list_assets() :: {:ok, [path()]} | {:error, term()}

  @type storage_reference :: {module(), GenServer.server()}

  @spec read_note(storage_reference(), id()) :: {:ok, String.t()} | {:error, term()}
  def read_note({driver, server}, id), do: driver.read_note(server, id)

  @spec write_note(storage_reference(), id(), String.t()) :: :ok | {:error, term()}
  def write_note({driver, server}, id, body), do: driver.write_note(server, id, body)

  @spec delete_note(storage_reference(), id()) :: :ok | {:error, term()}
  def delete_note({driver, server}, id), do: driver.delete_note(server, id)

  @spec list_notes(storage_reference()) :: {:ok, [id()]} | {:error, term()}
  def list_notes({driver, server}), do: driver.list_notes(server)

  @spec read_asset(storage_reference(), path()) :: {:ok, binary()} | {:error, term()}
  def read_asset({driver, server}, path), do: driver.read_asset(server, path)

  @spec write_asset(storage_reference(), path(), binary()) :: :ok | {:error, term()}
  def write_asset({driver, server}, path, data), do: driver.write_asset(server, path, data)

  @spec delete_asset(storage_reference(), path()) :: :ok | {:error, term()}
  def delete_asset({driver, server}, path), do: driver.delete_asset(server, path)

  @spec list_assets(storage_reference()) :: {:ok, [path()]} | {:error, term()}
  def list_assets({driver, server}), do: driver.list_assets(server)
end
