defmodule MarkdowWeb.OpenGraph.Cache do
  @moduledoc """
  Stores rendered Open Graph images on the instance's data volume.

  Keys are derived from the rendered card, so an entry never needs to be
  invalidated: new copy or a new palette produces a new key, and the old object
  simply stops being requested. The directory holds derived data only and can be
  deleted at any time; the next request renders the card again.
  """

  @doc "Reads a cached image, if it was rendered before."
  @spec get(String.t(), String.t()) :: {:ok, binary()} | {:error, :not_found | File.posix()}
  def get(directory, key) do
    case directory |> Path.join(key) |> File.read() do
      {:ok, bytes} -> {:ok, bytes}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Writes an image to the cache.

  The write goes to a temporary neighbour and is then renamed, so a reader never
  observes a half-written image.
  """
  @spec put(String.t(), String.t(), binary()) :: :ok | {:error, File.posix()}
  def put(directory, key, bytes) do
    path = Path.join(directory, key)
    scratch = path <> ".#{System.unique_integer([:positive])}"

    with :ok <- File.mkdir_p(directory),
         :ok <- File.write(scratch, bytes) do
      case File.rename(scratch, path) do
        :ok ->
          :ok

        {:error, reason} ->
          File.rm(scratch)
          {:error, reason}
      end
    end
  end
end
