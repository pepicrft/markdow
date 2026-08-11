defmodule Markdow.Storage.LocalFs do
  @moduledoc """
  Stores notes and assets below a local vault directory.

  Notes use their identifier as a relative path and receive an `.md` extension.
  Assets live below the `assets` directory. Traversal outside the vault is rejected.
  """

  use GenServer

  @behaviour Markdow.Storage

  @type server :: GenServer.server()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @impl Markdow.Storage
  def read_note(id), do: read_note(__MODULE__, id)

  @spec read_note(server(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def read_note(server, id), do: GenServer.call(server, {:read_note, id})

  @impl Markdow.Storage
  def write_note(id, body), do: write_note(__MODULE__, id, body)

  @spec write_note(server(), String.t(), String.t()) :: :ok | {:error, term()}
  def write_note(server, id, body), do: GenServer.call(server, {:write_note, id, body})

  @impl Markdow.Storage
  def delete_note(id), do: delete_note(__MODULE__, id)

  @spec delete_note(server(), String.t()) :: :ok | {:error, term()}
  def delete_note(server, id), do: GenServer.call(server, {:delete_note, id})

  @impl Markdow.Storage
  def list_notes, do: list_notes(__MODULE__)

  @spec list_notes(server()) :: {:ok, [String.t()]} | {:error, term()}
  def list_notes(server), do: GenServer.call(server, :list_notes)

  @impl Markdow.Storage
  def read_asset(path), do: read_asset(__MODULE__, path)

  @spec read_asset(server(), String.t()) :: {:ok, binary()} | {:error, term()}
  def read_asset(server, path), do: GenServer.call(server, {:read_asset, path})

  @impl Markdow.Storage
  def write_asset(path, data), do: write_asset(__MODULE__, path, data)

  @spec write_asset(server(), String.t(), binary()) :: :ok | {:error, term()}
  def write_asset(server, path, data), do: GenServer.call(server, {:write_asset, path, data})

  @impl Markdow.Storage
  def delete_asset(path), do: delete_asset(__MODULE__, path)

  @spec delete_asset(server(), String.t()) :: :ok | {:error, term()}
  def delete_asset(server, path), do: GenServer.call(server, {:delete_asset, path})

  @impl Markdow.Storage
  def list_assets, do: list_assets(__MODULE__)

  @spec list_assets(server()) :: {:ok, [String.t()]} | {:error, term()}
  def list_assets(server), do: GenServer.call(server, :list_assets)

  @impl GenServer
  def init(opts) do
    root = opts |> Keyword.fetch!(:path) |> Path.expand()

    with :ok <- File.mkdir_p(root), do: {:ok, %{root: root}}
  end

  @impl GenServer
  def handle_call({:read_note, id}, _from, state) do
    reply = with {:ok, path} <- note_path(state.root, id), do: File.read(path)
    {:reply, reply, state}
  end

  def handle_call({:write_note, id, body}, _from, state) do
    reply =
      with {:ok, path} <- note_path(state.root, id),
           do: atomic_write(path, body)

    {:reply, reply, state}
  end

  def handle_call({:delete_note, id}, _from, state) do
    reply = with {:ok, path} <- note_path(state.root, id), do: File.rm(path)
    {:reply, reply, state}
  end

  def handle_call(:list_notes, _from, state) do
    notes =
      state.root
      |> Path.join("**/*.md")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(&contains_symbolic_link?(state.root, &1))
      |> Enum.map(fn path ->
        Path.relative_to(path, state.root)
      end)
      |> Enum.reject(&(&1 == "assets" or String.starts_with?(&1, "assets/")))
      |> Enum.map(&Path.rootname(&1, ".md"))
      |> Enum.sort()

    {:reply, {:ok, notes}, state}
  end

  def handle_call({:read_asset, asset_path}, _from, state) do
    reply = with {:ok, path} <- asset_path(state.root, asset_path), do: File.read(path)
    {:reply, reply, state}
  end

  def handle_call({:write_asset, asset_path, data}, _from, state) do
    reply =
      with {:ok, path} <- asset_path(state.root, asset_path),
           do: atomic_write(path, data)

    {:reply, reply, state}
  end

  def handle_call({:delete_asset, asset_path}, _from, state) do
    reply = with {:ok, path} <- asset_path(state.root, asset_path), do: File.rm(path)
    {:reply, reply, state}
  end

  def handle_call(:list_assets, _from, state) do
    asset_root = Path.join(state.root, "assets")

    assets =
      asset_root
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(&contains_symbolic_link?(asset_root, &1))
      |> Enum.map(&Path.relative_to(&1, asset_root))
      |> Enum.sort()

    {:reply, {:ok, assets}, state}
  end

  defp note_path(root, id) when is_binary(id) do
    relative_path = id <> ".md"

    with :ok <- validate_relative_path(id),
         :ok <- reject_symbolic_links(root, relative_path),
         do: {:ok, Path.join(root, relative_path)}
  end

  defp note_path(_root, _id), do: {:error, :invalid_path}

  defp asset_path(root, path) when is_binary(path) do
    relative_path = Path.join("assets", path)

    with :ok <- validate_relative_path(path),
         :ok <- reject_symbolic_links(root, relative_path),
         do: {:ok, Path.join(root, relative_path)}
  end

  defp asset_path(_root, _path), do: {:error, :invalid_path}

  defp validate_relative_path(path) when is_binary(path) do
    segments = Path.split(path)

    if path != "" and Path.type(path) == :relative and
         Enum.all?(segments, &(&1 not in [".", "..", ""])),
       do: :ok,
       else: {:error, :invalid_path}
  end

  # Existing symbolic links are never followed. A vault can contain links created
  # outside Markdow, and following one would let an authenticated document request
  # read or write beyond the configured vault root.
  defp reject_symbolic_links(root, relative_path) do
    relative_path
    |> Path.split()
    |> Enum.reduce_while(root, fn segment, current_path ->
      candidate = Path.join(current_path, segment)

      case File.lstat(candidate) do
        {:ok, %File.Stat{type: :symlink}} -> {:halt, {:error, :invalid_path}}
        {:ok, _stat} -> {:cont, candidate}
        {:error, :enoent} -> {:cont, candidate}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      _path -> :ok
    end
  end

  defp contains_symbolic_link?(root, path) do
    relative_path = Path.relative_to(path, root)
    reject_symbolic_links(root, relative_path) != :ok
  end

  defp atomic_write(path, data) do
    temporary_path = path <> ".tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(temporary_path, data) do
      case File.rename(temporary_path, path) do
        :ok ->
          :ok

        {:error, reason} ->
          File.rm(temporary_path)
          {:error, reason}
      end
    end
  end
end
