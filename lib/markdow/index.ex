defmodule Markdow.Index do
  @moduledoc """
  Keeps PostgreSQL search records synchronized with the configured Markdown storage.

  Writes use a PostgreSQL transaction-level advisory lock, which coordinates index
  changes across every Markdow replica in a cluster.
  """

  import Ecto.Query

  alias Ecto.Adapters.SQL
  alias Markdow.Accounts
  alias Markdow.AgentAuth.AccessToken
  alias Markdow.AgentAuth.Assertion
  alias Markdow.AgentAuth.Event
  alias Markdow.AgentAuth.Registration
  alias Markdow.Index.Context
  alias Markdow.Index.Link
  alias Markdow.Index.Note
  alias Markdow.Index.Tag
  alias Markdow.Markdown
  alias Markdow.Repo
  alias Markdow.Storage
  alias Markdow.Storage.LocalFs

  @default_limit 50
  @maximum_limit 100
  @write_lock 6_668_046_993_284_456_817
  @registration_lock 7_566_567_577_261_413_932

  @spec context(keyword()) :: Context.t()
  def context(opts \\ []) do
    %Context{
      repo: Keyword.get(opts, :repo, Repo),
      storage: Keyword.get(opts, :storage, {LocalFs, LocalFs}),
      embedding_client: Keyword.get(opts, :embedding_client, Markdow.Embeddings.OpenAI),
      email_notifier: Keyword.get(opts, :email_notifier, Markdow.Accounts.EmailNotifier),
      embedding_secret_key:
        Keyword.get(
          opts,
          :embedding_secret_key,
          Application.get_env(:markdow, :embedding_secret_key)
        )
    }
  end

  @spec list_notes(keyword()) :: {:ok, map()} | {:error, term()}
  def list_notes(opts) when is_list(opts), do: list_notes(context(), opts)

  @spec list_notes(Context.t()) :: {:ok, map()} | {:error, term()}
  def list_notes(%Context{} = index), do: list_notes(index, [])

  @spec list_notes() :: {:ok, map()} | {:error, term()}
  def list_notes, do: list_notes(context(), [])

  @spec list_notes(Context.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_notes(%Context{} = index, opts) when is_list(opts),
    do: list_notes(index, Accounts.default_vault_id(), opts)

  @spec list_notes(Context.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_notes(%Context{} = index, vault_id, opts)
      when is_binary(vault_id) and is_list(opts) do
    with {:ok, _vault} <- Accounts.get_vault(vault_id, index.repo) do
      result_limit = limit(opts)
      result_offset = opts |> Keyword.get(:offset) |> non_negative_integer(0)

      notes =
        index.repo.all(
          from(note in Note,
            where: note.vault_id == ^vault_id,
            order_by: [asc: note.path],
            limit: ^result_limit,
            offset: ^result_offset
          )
        )

      total = index.repo.aggregate(from(note in Note, where: note.vault_id == ^vault_id), :count)

      {:ok,
       %{
         data: Enum.map(notes, &note_summary/1),
         pagination: %{limit: result_limit, offset: result_offset, total: total}
       }}
    end
  end

  @spec search(String.t()) :: {:ok, [map()]} | {:error, term()}
  def search(query) when is_binary(query), do: search(context(), query, [])

  @spec search(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(query, opts) when is_binary(query) and is_list(opts),
    do: search(context(), query, opts)

  @spec search(Context.t(), term()) :: {:ok, [map()]} | {:error, term()}
  def search(%Context{} = index, query), do: search(index, query, [])

  @spec search(Context.t(), term(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(%Context{} = index, query, opts),
    do: search(index, Accounts.default_vault_id(), query, opts)

  @spec search(Context.t(), String.t(), term(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def search(%Context{} = index, vault_id, query, opts),
    do: perform_search(index, vault_id, query, limit(opts))

  @spec get_note(String.t()) :: {:ok, map()} | {:error, term()}
  def get_note(id), do: get_note(context(), id)

  @spec get_note(Context.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_note(%Context{} = index, id),
    do: get_note(index, Accounts.default_vault_id(), id)

  @spec get_note(Context.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_note(%Context{} = index, vault_id, id), do: fetch_note(index, vault_id, id)

  @spec backlinks(String.t()) :: {:ok, [map()]} | {:error, term()}
  def backlinks(id), do: backlinks(context(), id)

  @spec backlinks(Context.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def backlinks(%Context{} = index, id),
    do: backlinks(index, Accounts.default_vault_id(), id)

  @spec backlinks(Context.t(), String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def backlinks(%Context{} = index, vault_id, id), do: fetch_backlinks(index, vault_id, id)

  @spec graph(String.t()) :: {:ok, map()} | {:error, term()}
  def graph(id), do: graph(context(), id, [])

  @spec graph(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def graph(id, opts) when is_binary(id) and is_list(opts), do: graph(context(), id, opts)

  @spec graph(Context.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def graph(%Context{} = index, id), do: graph(index, id, [])

  @spec graph(Context.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def graph(%Context{} = index, id, opts) do
    graph(index, Accounts.default_vault_id(), id, opts)
  end

  @spec graph(Context.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def graph(%Context{} = index, vault_id, id, opts) do
    depth = opts |> Keyword.get(:depth) |> positive_integer(1) |> min(3)
    build_graph(index, vault_id, id, depth)
  end

  @spec write_note(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def write_note(id, body) when is_binary(id) and is_binary(body),
    do: write_note(context(), id, body, [])

  @spec write_note(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def write_note(id, body, opts)
      when is_binary(id) and is_binary(body) and is_list(opts),
      do: write_note(context(), id, body, opts)

  @spec write_note(Context.t(), term(), term()) :: {:ok, map()} | {:error, term()}
  def write_note(%Context{} = index, id, body), do: write_note(index, id, body, [])

  @spec write_note(Context.t(), term(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def write_note(%Context{} = index, id, body, opts)
      when is_binary(id) and is_binary(body) and is_list(opts),
      do: write_note(index, Accounts.default_vault_id(), id, body, opts)

  def write_note(%Context{}, _id, _body, _opts), do: {:error, :invalid_note}

  @spec write_note(Context.t(), term(), term(), term(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def write_note(%Context{} = index, vault_id, id, body, opts)
      when is_binary(vault_id) and is_binary(id) and is_binary(body) and is_list(opts),
      do: persist_note(index, vault_id, id, body, opts)

  def write_note(%Context{}, _vault_id, _id, _body, _opts), do: {:error, :invalid_note}

  @spec delete_note(String.t()) :: :ok | {:error, term()}
  def delete_note(id), do: delete_note(context(), id)

  @spec delete_note(Context.t(), term()) :: :ok | {:error, term()}
  def delete_note(%Context{} = index, id) when is_binary(id),
    do: delete_note(index, Accounts.default_vault_id(), id)

  def delete_note(%Context{}, _id), do: {:error, :invalid_note}

  @spec delete_note(Context.t(), term(), term()) :: :ok | {:error, term()}
  def delete_note(%Context{} = index, vault_id, id)
      when is_binary(vault_id) and is_binary(id),
      do: remove_note(index, vault_id, id)

  def delete_note(%Context{}, _vault_id, _id), do: {:error, :invalid_note}

  @spec rebuild!() :: :ok | {:error, term()}
  def rebuild!, do: rebuild!(context())

  @spec rebuild!(Context.t()) :: :ok | {:error, term()}
  def rebuild!(%Context{} = index), do: rebuild!(index, Accounts.default_vault_id())

  @spec rebuild!(Context.t(), String.t()) :: :ok | {:error, term()}
  def rebuild!(%Context{} = index, vault_id), do: rebuild(index, vault_id)

  @spec health() :: :ok | {:error, term()}
  def health, do: health(context())

  @spec health(Context.t()) :: :ok | {:error, term()}
  def health(%Context{} = index) do
    case SQL.query(index.repo, "SELECT 1", []) do
      {:ok, %{rows: [[1]]}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list_documents(Context.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def list_documents(%Context{} = index, vault_id) when is_binary(vault_id) do
    with {:ok, vault} <- Accounts.get_vault(vault_id, index.repo),
         {:ok, stored_assets} <- Storage.list_assets(index.storage) do
      notes =
        index.repo.all(
          from(note in Note,
            where: note.vault_id == ^vault_id,
            order_by: [asc: note.path],
            select: %{path: note.path, updated_at: note.updated_at}
          )
        )

      note_documents =
        Enum.map(notes, fn note ->
          %{
            path: note.path <> ".md",
            kind: "note",
            media_type: "text/markdown",
            updated_at: note.updated_at
          }
        end)

      asset_documents =
        vault
        |> vault_asset_paths(stored_assets)
        |> Enum.map(fn path ->
          %{path: path, kind: "asset", media_type: media_type(path), updated_at: nil}
        end)

      {:ok, Enum.sort_by(note_documents ++ asset_documents, & &1.path)}
    end
  end

  @spec read_document(Context.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def read_document(%Context{} = index, vault_id, path)
      when is_binary(vault_id) and is_binary(path) do
    with :ok <- validate_document_path(path) do
      if markdown_document?(path),
        do: read_markdown_document(index, vault_id, path),
        else: read_asset_document(index, vault_id, path)
    end
  end

  @spec write_document(Context.t(), String.t(), String.t(), binary()) ::
          {:ok, map()} | {:error, term()}
  def write_document(%Context{} = index, vault_id, path, data)
      when is_binary(vault_id) and is_binary(path) and is_binary(data) do
    with :ok <- validate_document_path(path),
         :ok <- validate_document_size(data) do
      if markdown_document?(path),
        do: write_markdown_document(index, vault_id, path, data),
        else: write_asset_document(index, vault_id, path, data)
    end
  end

  @spec delete_document(Context.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete_document(%Context{} = index, vault_id, path)
      when is_binary(vault_id) and is_binary(path) do
    with :ok <- validate_document_path(path) do
      if markdown_document?(path),
        do: delete_markdown_document(index, vault_id, path),
        else: delete_asset_document(index, vault_id, path)
    end
  end

  @doc false
  @spec agent_auth(term()) :: term()
  def agent_auth(operation), do: agent_auth(context(), operation)

  @doc false
  @spec agent_auth(Context.t(), term()) :: term()
  def agent_auth(%Context{} = index, operation), do: perform_agent_auth(index, operation)

  defp fetch_note(index, vault_id, id) do
    case index.repo.get_by(Note, vault_id: vault_id, id: id) do
      nil ->
        {:error, :not_found}

      note ->
        with {:ok, vault} <- Accounts.get_vault(vault_id, index.repo),
             {:ok, body} <- Storage.read_note(index.storage, Accounts.storage_key(vault, id)) do
          tags =
            index.repo.all(
              from(tag in Tag,
                where: tag.vault_id == ^vault_id and tag.note_id == ^id,
                order_by: [asc: tag.tag],
                select: tag.tag
              )
            )

          links =
            index.repo.all(
              from(link in Link,
                where: link.vault_id == ^vault_id and link.source_id == ^id,
                order_by: [asc: link.target_id],
                select: %{target_id: link.target_id, context: link.context}
              )
            )

          {:ok,
           note
           |> note_summary()
           |> Map.put(:body, body)
           |> Map.put(:tags, tags)
           |> Map.put(:links, links)}
        end
    end
  end

  defp read_markdown_document(index, vault_id, path) do
    note_path = Path.rootname(path, Path.extname(path))

    case index.repo.get_by(Note, vault_id: vault_id, path: note_path) do
      nil -> {:error, :not_found}
      note -> document_from_note(index, vault_id, path, note.id)
    end
  end

  defp document_from_note(index, vault_id, path, note_id) do
    with {:ok, note} <- fetch_note(index, vault_id, note_id) do
      {:ok,
       %{
         vault_id: vault_id,
         id: note_id,
         path: path,
         kind: "note",
         media_type: "text/markdown",
         size: byte_size(note.body),
         data: note.body
       }}
    end
  end

  defp read_asset_document(index, vault_id, path) do
    with {:ok, vault} <- Accounts.get_vault(vault_id, index.repo),
         {:ok, data} <- Storage.read_asset(index.storage, Accounts.storage_key(vault, path)) do
      {:ok,
       %{
         vault_id: vault_id,
         path: path,
         kind: "asset",
         media_type: media_type(path),
         size: byte_size(data),
         data: data
       }}
    else
      {:error, :enoent} -> {:error, :not_found}
      error -> error
    end
  end

  defp write_markdown_document(index, vault_id, path, data) do
    if String.valid?(data) do
      note_path = Path.rootname(path, Path.extname(path))

      note_id =
        case index.repo.get_by(Note, vault_id: vault_id, path: note_path) do
          nil -> note_path
          note -> note.id
        end

      with {:ok, _note} <- write_note(index, vault_id, note_id, data, path: note_path),
           do: read_markdown_document(index, vault_id, path)
    else
      {:error, :invalid_utf8}
    end
  end

  defp write_asset_document(index, vault_id, path, data) do
    with {:ok, vault} <- Accounts.get_vault(vault_id, index.repo),
         :ok <- Storage.write_asset(index.storage, Accounts.storage_key(vault, path), data) do
      {:ok,
       %{
         vault_id: vault_id,
         path: path,
         kind: "asset",
         media_type: media_type(path),
         size: byte_size(data)
       }}
    end
  end

  defp delete_markdown_document(index, vault_id, path) do
    note_path = Path.rootname(path, Path.extname(path))

    case index.repo.get_by(Note, vault_id: vault_id, path: note_path) do
      nil -> {:error, :not_found}
      note -> delete_note(index, vault_id, note.id)
    end
  end

  defp delete_asset_document(index, vault_id, path) do
    with {:ok, vault} <- Accounts.get_vault(vault_id, index.repo),
         :ok <- Storage.delete_asset(index.storage, Accounts.storage_key(vault, path)) do
      :ok
    else
      {:error, :enoent} -> {:error, :not_found}
      error -> error
    end
  end

  defp vault_asset_paths(%{storage_prefix: ""}, storage_paths) do
    Enum.reject(storage_paths, &String.starts_with?(&1, "vaults/"))
  end

  defp vault_asset_paths(%{storage_prefix: prefix}, storage_paths) do
    marker = prefix <> "/"

    storage_paths
    |> Enum.filter(&String.starts_with?(&1, marker))
    |> Enum.map(&String.replace_prefix(&1, marker, ""))
  end

  defp validate_document_path(path) do
    segments = Path.split(path)

    if path != "" and byte_size(path) <= 1_024 and Path.type(path) == :relative and
         Enum.all?(segments, &(&1 not in [".", "..", ""])) and
         Enum.join(segments, "/") == path,
       do: :ok,
       else: {:error, :invalid_path}
  end

  defp validate_document_size(data) do
    if byte_size(data) <= 5 * 1_024 * 1_024,
      do: :ok,
      else: {:error, :document_too_large}
  end

  defp markdown_document?(path), do: String.downcase(Path.extname(path)) == ".md"
  defp media_type(path), do: MIME.from_path(path)

  defp persist_note(index, vault_id, id, body, opts) do
    with {:ok, vault} <- Accounts.get_vault(vault_id, index.repo) do
      persist_vault_note(index, vault, vault_id, id, body, opts)
    end
  end

  defp persist_vault_note(index, vault, vault_id, id, body, opts) do
    storage_id = Accounts.storage_key(vault, id)
    parsed = Markdown.parse(id, body, opts)

    transaction(index.repo, fn ->
      persist_note_transaction(index, vault_id, id, body, parsed, storage_id)
    end)
  end

  defp persist_note_transaction(index, vault_id, id, body, parsed, storage_id) do
    with :ok <- acquire_write_lock(index.repo) do
      previous = Storage.read_note(index.storage, storage_id)

      persist_note_locked(index, vault_id, id, body, parsed, storage_id, previous)
    end
  end

  # Storage changes and their index transaction share the same advisory lock.
  # The file must be written before it can be read back into the response, but
  # restoring a rejected write before releasing the lock prevents another
  # replica from committing a newer index row against the restored old file.
  defp persist_note_locked(index, vault_id, id, body, parsed, storage_id, previous) do
    case Storage.write_note(index.storage, storage_id, body) do
      :ok ->
        with :ok <- upsert_note(index.repo, vault_id, id, body, parsed),
             :ok <- replace_tags(index.repo, vault_id, id, parsed.tags),
             :ok <- refresh_links(index.repo, vault_id) do
          fetch_note(index, vault_id, id)
        else
          {:error, reason} ->
            restore_persisted_note(index.storage, storage_id, previous, reason)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upsert_note(repo, vault_id, id, body, parsed) do
    attrs = %{
      vault_id: vault_id,
      id: id,
      title: parsed.title,
      path: parsed.path,
      body: body,
      metadata: parsed.metadata
    }

    result =
      %Note{vault_id: vault_id, id: id}
      |> Note.changeset(attrs)
      |> repo.insert(
        conflict_target: [:vault_id, :id],
        on_conflict: {:replace, [:title, :path, :body, :metadata, :updated_at]}
      )

    case result do
      {:ok, _note} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp replace_tags(repo, vault_id, id, tags) do
    repo.delete_all(from(tag in Tag, where: tag.vault_id == ^vault_id and tag.note_id == ^id))

    case Enum.map(tags, &%{vault_id: vault_id, note_id: id, tag: &1}) do
      [] ->
        :ok

      entries ->
        repo.insert_all(Tag, entries, on_conflict: :nothing)
        :ok
    end
  end

  defp remove_note(index, vault_id, id) do
    with {:ok, vault} <- Accounts.get_vault(vault_id, index.repo) do
      remove_vault_note(index, vault, vault_id, id)
    end
  end

  defp remove_vault_note(index, vault, vault_id, id) do
    storage_id = Accounts.storage_key(vault, id)
    transaction(index.repo, fn -> remove_note_transaction(index, vault_id, id, storage_id) end)
  end

  defp remove_note_transaction(index, vault_id, id, storage_id) do
    with :ok <- acquire_write_lock(index.repo),
         {:ok, _note} <- fetch_note(index, vault_id, id) do
      remove_note_locked(index, vault_id, id, storage_id)
    end
  end

  defp remove_note_locked(index, vault_id, id, storage_id) do
    case Storage.delete_note(index.storage, storage_id) do
      :ok ->
        index.repo.delete_all(
          from(note in Note, where: note.vault_id == ^vault_id and note.id == ^id)
        )

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp rebuild(index, vault_id) do
    with {:ok, vault} <- Accounts.get_vault(vault_id, index.repo) do
      transaction(index.repo, fn -> rebuild_transaction(index, vault_id, vault) end)
    end
  end

  defp rebuild_transaction(index, vault_id, vault) do
    with :ok <- acquire_write_lock(index.repo),
         {:ok, storage_ids} <- Storage.list_notes(index.storage) do
      ids = vault_note_ids(vault, storage_ids)
      rebuild_index_locked(index, vault_id, vault, ids)
    end
  end

  defp rebuild_index_locked(index, vault_id, vault, ids) do
    index.repo.delete_all(from(note in Note, where: note.vault_id == ^vault_id))

    with :ok <- index_storage_notes(index, vault_id, vault, ids) do
      refresh_links(index.repo, vault_id)
    end
  end

  defp index_storage_notes(index, vault_id, vault, ids) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      storage_id = Accounts.storage_key(vault, id)

      with {:ok, body} <- Storage.read_note(index.storage, storage_id),
           parsed = Markdown.parse(id, body),
           :ok <- upsert_note(index.repo, vault_id, id, body, parsed),
           :ok <- replace_tags(index.repo, vault_id, id, parsed.tags) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, {id, reason}}}
      end
    end)
  end

  defp refresh_links(repo, vault_id) do
    notes =
      repo.all(
        from(note in Note,
          where: note.vault_id == ^vault_id,
          select: {note.id, note.title, note.path, note.body}
        )
      )

    repo.delete_all(from(link in Link, where: link.vault_id == ^vault_id))

    entries = link_entries(vault_id, notes, link_lookup(notes))

    if entries != [] do
      repo.insert_all(Link, entries)
    end

    :ok
  end

  defp link_entries(vault_id, notes, lookup) do
    Enum.reduce(notes, %{}, fn {source_id, _title, _path, body}, entries ->
      Enum.reduce(
        Markdown.links(body),
        entries,
        &put_link_entry(&2, &1, vault_id, source_id, lookup)
      )
    end)
    |> Map.values()
  end

  defp put_link_entry(entries, link, vault_id, source_id, lookup) do
    case Map.fetch(lookup, link.target) do
      {:ok, target_id} ->
        Map.put(entries, {source_id, target_id}, %{
          vault_id: vault_id,
          source_id: source_id,
          target_id: target_id,
          context: link.context
        })

      :error ->
        entries
    end
  end

  defp link_lookup(notes) do
    Enum.reduce(notes, %{}, fn {id, title, path, _body}, lookup ->
      [id, title, path, Path.basename(path)]
      |> Enum.map(&Markdown.normalize_link_target/1)
      |> Enum.reduce(lookup, &Map.put_new(&2, &1, id))
    end)
  end

  defp vault_note_ids(%{storage_prefix: ""}, storage_ids) do
    Enum.reject(storage_ids, &String.starts_with?(&1, "vaults/"))
  end

  defp vault_note_ids(%{storage_prefix: prefix}, storage_ids) do
    marker = prefix <> "/"

    storage_ids
    |> Enum.filter(&String.starts_with?(&1, marker))
    |> Enum.map(&String.replace_prefix(&1, marker, ""))
  end

  defp perform_search(_index, _vault_id, query, _limit) when query in [nil, ""], do: {:ok, []}

  defp perform_search(index, vault_id, query, result_limit) when is_binary(query) do
    with {:ok, _vault} <- Accounts.get_vault(vault_id, index.repo) do
      if String.trim(query) == "" do
        {:ok, []}
      else
        search_postgres(index.repo, vault_id, query, result_limit)
      end
    end
  end

  defp perform_search(_index, _vault_id, _query, _limit), do: {:error, :invalid_query}

  defp search_postgres(repo, vault_id, query, result_limit) do
    statement = """
    SELECT vault_id, id, title, path, metadata, inserted_at, updated_at,
           ts_headline(
             'simple', body, websearch_to_tsquery('simple', $2),
             'StartSel=, StopSel=, MaxWords=24, MinWords=8, ShortWord=2, FragmentDelimiter= … '
           ) AS snippet,
           ts_rank_cd(search_vector, websearch_to_tsquery('simple', $2)) AS rank
    FROM notes
    WHERE vault_id = $1 AND search_vector @@ websearch_to_tsquery('simple', $2)
    ORDER BY rank DESC, path ASC
    LIMIT $3
    """

    case SQL.query(repo, statement, [vault_id, query, result_limit]) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &search_result/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp search_result([
         vault_id,
         id,
         title,
         path,
         metadata,
         inserted_at,
         updated_at,
         snippet,
         rank
       ]) do
    %{
      vault_id: vault_id,
      id: id,
      title: title,
      path: path,
      metadata: metadata,
      created_at: inserted_at,
      updated_at: updated_at,
      snippet: snippet,
      rank: rank
    }
  end

  defp fetch_backlinks(index, vault_id, id) do
    case index.repo.get_by(Note, vault_id: vault_id, id: id) do
      nil ->
        {:error, :not_found}

      _note ->
        backlinks =
          index.repo.all(
            from(link in Link,
              join: note in Note,
              on: note.vault_id == link.vault_id and note.id == link.source_id,
              where: link.vault_id == ^vault_id and link.target_id == ^id,
              order_by: [asc: note.path],
              select: {note, link.context}
            )
          )

        {:ok,
         Enum.map(backlinks, fn {note, link_context} ->
           note |> note_summary() |> Map.put(:context, link_context)
         end)}
    end
  end

  defp build_graph(index, vault_id, id, depth) do
    case index.repo.get_by(Note, vault_id: vault_id, id: id) do
      nil -> {:error, :not_found}
      _note -> graph_from_note(index, vault_id, id, depth)
    end
  end

  defp graph_from_note(index, vault_id, id, depth) do
    statement = """
    WITH RECURSIVE reachable(id, depth) AS (
      SELECT $2::text, 0
      UNION
      SELECT links.target_id, reachable.depth + 1
      FROM links
      JOIN reachable ON links.source_id = reachable.id
      WHERE links.vault_id = $1 AND reachable.depth < $3
    )
    SELECT notes.vault_id, notes.id, notes.title, notes.path, notes.metadata,
           notes.inserted_at, notes.updated_at, MIN(reachable.depth)
    FROM reachable
    JOIN notes ON notes.vault_id = $1 AND notes.id = reachable.id
    GROUP BY notes.vault_id, notes.id
    ORDER BY MIN(reachable.depth), notes.path
    """

    with {:ok, %{rows: node_rows}} <- SQL.query(index.repo, statement, [vault_id, id, depth]) do
      node_ids = node_rows |> Enum.map(&Enum.at(&1, 1)) |> MapSet.new()
      edges = graph_edges(index.repo, vault_id, node_ids)

      {:ok,
       %{
         vault_id: vault_id,
         root_id: id,
         depth: depth,
         nodes: Enum.map(node_rows, &graph_node/1),
         edges: edges
       }}
    end
  end

  defp graph_edges(repo, vault_id, node_ids) do
    repo.all(from(link in Link, where: link.vault_id == ^vault_id))
    |> Enum.filter(fn link ->
      MapSet.member?(node_ids, link.source_id) and MapSet.member?(node_ids, link.target_id)
    end)
    |> Enum.map(fn link ->
      %{source_id: link.source_id, target_id: link.target_id, context: link.context}
    end)
  end

  defp graph_node([vault_id, id, title, path, metadata, inserted_at, updated_at, depth]) do
    %{
      vault_id: vault_id,
      id: id,
      title: title,
      path: path,
      metadata: metadata,
      created_at: inserted_at,
      updated_at: updated_at,
      depth: depth
    }
  end

  defp note_summary(note) do
    %{
      vault_id: note.vault_id,
      id: note.id,
      title: note.title,
      path: note.path,
      metadata: note.metadata,
      created_at: note.inserted_at,
      updated_at: note.updated_at
    }
  end

  defp restore_persisted_note(storage, id, previous, reason) do
    restore_storage(storage, id, previous)
    {:error, reason}
  end

  defp restore_storage(storage, id, {:ok, body}), do: Storage.write_note(storage, id, body)
  defp restore_storage(storage, id, {:error, :enoent}), do: Storage.delete_note(storage, id)
  defp restore_storage(_storage, _id, _previous), do: :ok

  defp perform_agent_auth(index, {:registration_count_since, since, address}) do
    query = from(registration in Registration, where: registration.created_at >= ^since)

    query =
      if is_binary(address),
        do: from(registration in query, where: registration.registration_address == ^address),
        else: query

    count = index.repo.aggregate(query, :count)

    {:ok, count}
  end

  defp perform_agent_auth(index, {:registration_count_since, since}),
    do: perform_agent_auth(index, {:registration_count_since, since, nil})

  defp perform_agent_auth(index, {:create_registration, registration}) do
    transaction(index.repo, fn -> insert_registration(index.repo, registration) end)
  end

  defp perform_agent_auth(
         index,
         {:create_rate_limited_registration, registration, since, address_limit, global_limit}
       ) do
    transaction(index.repo, fn ->
      with :ok <- acquire_registration_lock(index.repo),
           :ok <-
             enforce_registration_limits(
               index.repo,
               since,
               registration.registration_address,
               address_limit,
               global_limit
             ) do
        insert_registration(index.repo, registration)
      end
    end)
  end

  defp perform_agent_auth(index, {:registration_by_claim_token, hash}),
    do: find_registration(index.repo, :claim_token_hash, hash)

  defp perform_agent_auth(index, {:registration_by_claim_attempt, hash}),
    do: find_registration(index.repo, :claim_attempt_token_hash, hash)

  defp perform_agent_auth(index, {:registration_by_id, id}),
    do: find_registration(index.repo, :id, id)

  defp perform_agent_auth(index, {:mark_polled, id, polled_at}) do
    index.repo.update_all(
      from(registration in Registration, where: registration.id == ^id),
      set: [last_polled_at: polled_at]
    )

    :ok
  end

  defp perform_agent_auth(index, {:record_claim_address, id, address}) do
    index.repo.update_all(
      from(
        registration in Registration,
        where: registration.id == ^id and registration.status == "pending"
      ),
      set: [claim_address: address]
    )

    :ok
  end

  defp perform_agent_auth(index, {:record_sign_in_failure, id, address, attempt_limit}) do
    index.repo.transaction(fn ->
      registration =
        index.repo.one(
          from(registration in Registration, where: registration.id == ^id, lock: "FOR UPDATE")
        )

      case record_locked_sign_in_failure(index.repo, registration, address, attempt_limit) do
        :ok -> :ok
        {:error, reason} when is_atom(reason) -> {:domain_error, reason}
        {:error, reason} -> index.repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:ok, {:domain_error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp perform_agent_auth(
         index,
         {:confirm_claim, id, code_hashes, user_id, claimed_at, email_verified, address,
          attempt_limit}
       ) do
    index.repo.transaction(fn ->
      registration =
        index.repo.one(
          from(registration in Registration, where: registration.id == ^id, lock: "FOR UPDATE")
        )

      case confirm_locked_claim(
             index.repo,
             registration,
             code_hashes,
             user_id,
             claimed_at,
             email_verified,
             address,
             attempt_limit
           ) do
        :ok -> :ok
        {:error, reason} when is_atom(reason) -> {:domain_error, reason}
        {:error, reason} -> index.repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:ok, {:domain_error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp perform_agent_auth(index, {:expire_registration, id, expired_at}) do
    transaction(index.repo, fn ->
      {count, _records} =
        index.repo.update_all(
          from(
            registration in Registration,
            where: registration.id == ^id and registration.status == "pending"
          ),
          set: [status: "expired"]
        )

      if count == 1 do
        insert_agent_event(index.repo, id, "registration.expired", %{expired_at: expired_at})
      else
        :ok
      end
    end)
  end

  defp perform_agent_auth(index, {:expire_due_registrations, expired_at}) do
    transaction(index.repo, fn ->
      registrations =
        index.repo.all(
          from(registration in Registration,
            where: registration.status == "pending" and registration.expires_at <= ^expired_at,
            lock: "FOR UPDATE SKIP LOCKED"
          )
        )

      with :ok <- expire_registrations(index.repo, registrations, expired_at) do
        {:ok, length(registrations)}
      end
    end)
  end

  defp perform_agent_auth(index, {:put_access_token, token}) do
    attrs = Map.drop(token, [:value])

    transaction(index.repo, fn ->
      with {:ok, _record} <- index.repo.insert(struct(AccessToken, attrs)) do
        insert_agent_event(index.repo, token.registration_id, "token.issued", %{
          scope: token.scopes
        })
      end
    end)
  end

  defp perform_agent_auth(index, {:consume_assertion, hash, expires_at, current_time}) do
    transaction(index.repo, fn ->
      index.repo.delete_all(
        from(assertion in Assertion, where: assertion.expires_at <= ^current_time)
      )

      timestamp = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      case index.repo.insert_all(
             Assertion,
             [%{jti_hash: hash, expires_at: expires_at, inserted_at: timestamp}],
             on_conflict: :nothing
           ) do
        {1, _records} -> :ok
        {0, _records} -> {:error, :assertion_replayed}
      end
    end)
  end

  defp perform_agent_auth(index, {:access_token, hash}) do
    result =
      index.repo.one(
        from(access_token in AccessToken,
          join: registration in Registration,
          on: registration.id == access_token.registration_id,
          where: access_token.token_hash == ^hash,
          select: %{
            scopes: access_token.scopes,
            expires_at: access_token.expires_at,
            revoked_at: access_token.revoked_at,
            resource: access_token.resource,
            registration_id: registration.id,
            registration_status: registration.status,
            claim_email: registration.claim_email,
            user_id: registration.claimed_by_user_id
          }
        )
      )

    if is_nil(result), do: {:error, :not_found}, else: {:ok, result}
  end

  defp perform_agent_auth(index, {:revoke_access_token, hash, revoked_at}) do
    transaction(index.repo, fn -> revoke_access_token(index.repo, hash, revoked_at) end)
  end

  defp perform_agent_auth(index, {:revoke_user_access_tokens, user_id, revoked_at}) do
    transaction(index.repo, fn ->
      registrations =
        index.repo.all(
          from(registration in Registration,
            where:
              registration.claimed_by_user_id == ^user_id and
                registration.status == "claimed",
            lock: "FOR UPDATE"
          )
        )

      tokens =
        index.repo.all(
          from(access_token in AccessToken,
            join: registration in Registration,
            on: registration.id == access_token.registration_id,
            where:
              registration.claimed_by_user_id == ^user_id and
                is_nil(access_token.revoked_at),
            select: %{hash: access_token.token_hash, registration_id: registration.id},
            lock: "FOR UPDATE OF a0"
          )
        )

      with :ok <- revoke_user_tokens(index.repo, tokens, revoked_at),
           :ok <- revoke_registrations(index.repo, registrations, revoked_at) do
        {:ok, length(tokens)}
      end
    end)
  end

  defp perform_agent_auth(index, {:record_event, registration_id, name, metadata}) do
    insert_agent_event(index.repo, registration_id, name, metadata)
  end

  defp perform_agent_auth(_index, _operation), do: {:error, :unsupported_operation}

  defp confirm_locked_claim(
         _repo,
         nil,
         _code_hash,
         _user_id,
         _at,
         _email_verified,
         _address,
         _limit
       ),
       do: {:error, :invalid_claim_token}

  defp confirm_locked_claim(
         repo,
         %{status: "pending"} = registration,
         code_hashes,
         user_id,
         claimed_at,
         email_verified,
         address,
         attempt_limit
       ) do
    if valid_claim_code?(registration.user_code_hash, code_hashes) do
      claim_locked_registration(
        repo,
        registration,
        user_id,
        claimed_at,
        email_verified,
        address
      )
    else
      reject_claim_code(repo, registration, address, attempt_limit)
    end
  end

  defp confirm_locked_claim(
         _repo,
         %{status: "claimed"},
         _code_hash,
         _user_id,
         _claimed_at,
         _email_verified,
         _address,
         _attempt_limit
       ),
       do: {:error, :already_claimed}

  defp confirm_locked_claim(
         _repo,
         _registration,
         _code_hash,
         _user_id,
         _claimed_at,
         _email_verified,
         _address,
         _attempt_limit
       ),
       do: {:error, :expired_token}

  defp valid_claim_code?(stored_hash, code_hashes) when is_list(code_hashes) do
    Enum.reduce(code_hashes, false, fn code_hash, valid? ->
      secure_digest_match?(stored_hash, code_hash) or valid?
    end)
  end

  defp valid_claim_code?(stored_hash, code_hash),
    do: secure_digest_match?(stored_hash, code_hash)

  defp record_locked_sign_in_failure(_repo, nil, _address, _limit),
    do: {:error, :invalid_claim_token}

  defp record_locked_sign_in_failure(
         repo,
         %{status: "pending"} = registration,
         address,
         attempt_limit
       ) do
    failed_attempts = registration.failed_sign_in_attempts + 1
    expired? = failed_attempts >= attempt_limit

    updates =
      if expired?,
        do: %{failed_sign_in_attempts: failed_attempts, status: "expired"},
        else: %{failed_sign_in_attempts: failed_attempts}

    registration
    |> Ecto.Changeset.change(updates)
    |> repo.update()
    |> finish_sign_in_failure(repo, registration.id, address, expired?)
  end

  defp record_locked_sign_in_failure(_repo, _registration, _address, _limit),
    do: {:error, :expired_token}

  defp expire_registrations(repo, registrations, expired_at) do
    Enum.reduce_while(registrations, :ok, fn registration, :ok ->
      case expire_registration(repo, registration, expired_at) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp expire_registration(repo, registration, expired_at) do
    with {:ok, _registration} <-
           registration
           |> Ecto.Changeset.change(status: "expired")
           |> repo.update() do
      insert_agent_event(repo, registration.id, "registration.expired", %{
        expired_at: expired_at,
        reason: "registration_ttl"
      })
    end
  end

  defp revoke_user_tokens(repo, tokens, revoked_at) do
    Enum.reduce_while(tokens, :ok, fn token, :ok ->
      case revoke_user_token(repo, token, revoked_at) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp revoke_user_token(repo, token, revoked_at) do
    repo.update_all(
      from(access_token in AccessToken, where: access_token.token_hash == ^token.hash),
      set: [revoked_at: revoked_at]
    )

    insert_agent_event(repo, token.registration_id, "token.revoked", %{
      reason: "user_bulk_revocation"
    })
  end

  defp revoke_registrations(repo, registrations, revoked_at) do
    Enum.reduce_while(registrations, :ok, fn registration, :ok ->
      case revoke_registration(repo, registration, revoked_at) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp revoke_registration(repo, registration, revoked_at) do
    with {:ok, _registration} <-
           registration
           |> Ecto.Changeset.change(status: "revoked")
           |> repo.update() do
      insert_agent_event(repo, registration.id, "registration.revoked", %{
        reason: "user_bulk_revocation",
        revoked_at: revoked_at
      })
    end
  end

  defp claim_locked_registration(
         repo,
         registration,
         user_id,
         claimed_at,
         email_verified,
         address
       ) do
    registration
    |> Ecto.Changeset.change(%{
      status: "claimed",
      claimed_at: claimed_at,
      claimed_by_user_id: user_id,
      email_verified: email_verified,
      confirmed_address: address
    })
    |> repo.update()
    |> finish_claim(repo, registration.id, user_id, address)
  end

  defp finish_claim({:ok, _registration}, repo, registration_id, user_id, address) do
    insert_agent_event(repo, registration_id, "claim.confirmed", %{
      claimed_by_user_id: user_id,
      network_address: address
    })
  end

  defp finish_claim({:error, reason}, _repo, _registration_id, _user_id, _address),
    do: {:error, reason}

  defp reject_claim_code(repo, registration, address, attempt_limit) do
    failed_attempts = registration.failed_claim_attempts + 1
    expired? = failed_attempts >= attempt_limit

    updates =
      if expired?,
        do: %{failed_claim_attempts: failed_attempts, status: "expired"},
        else: %{failed_claim_attempts: failed_attempts}

    registration
    |> Ecto.Changeset.change(updates)
    |> repo.update()
    |> finish_claim_rejection(repo, registration.id, address, expired?)
  end

  defp finish_claim_rejection({:error, reason}, _repo, _id, _address, _expired?),
    do: {:error, reason}

  defp finish_claim_rejection({:ok, _registration}, _repo, _id, _address, false),
    do: {:error, :invalid_user_code}

  defp finish_claim_rejection({:ok, _registration}, repo, id, address, true) do
    case insert_agent_event(repo, id, "registration.expired", %{
           reason: "claim_attempt_limit",
           network_address: address
         }) do
      :ok -> {:error, :expired_token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish_sign_in_failure({:error, reason}, _repo, _id, _address, _expired?),
    do: {:error, reason}

  defp finish_sign_in_failure({:ok, _registration}, _repo, _id, _address, false), do: :ok

  defp finish_sign_in_failure({:ok, _registration}, repo, id, address, true) do
    case insert_agent_event(repo, id, "registration.expired", %{
           reason: "sign_in_attempt_limit",
           network_address: address
         }) do
      :ok -> {:error, :expired_token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp revoke_access_token(repo, hash, revoked_at) do
    token =
      repo.one(
        from(access_token in AccessToken,
          where: access_token.token_hash == ^hash,
          lock: "FOR UPDATE"
        )
      )

    case token do
      nil ->
        :ok

      %{revoked_at: revoked} when not is_nil(revoked) ->
        :ok

      token ->
        with {:ok, _token} <-
               token |> Ecto.Changeset.change(revoked_at: revoked_at) |> repo.update() do
          insert_agent_event(repo, token.registration_id, "token.revoked", %{})
        end
    end
  end

  defp secure_digest_match?(expected, actual) do
    byte_size(expected) == byte_size(actual) and Plug.Crypto.secure_compare(expected, actual)
  end

  defp find_registration(repo, attribute, value) do
    query = from(registration in Registration, where: field(registration, ^attribute) == ^value)

    case repo.one(query) do
      nil -> {:error, :not_found}
      registration -> {:ok, registration_map(registration)}
    end
  end

  defp registration_map(registration) do
    registration
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end

  defp insert_agent_event(repo, registration_id, name, metadata) do
    result =
      repo.insert(%Event{
        registration_id: registration_id,
        name: name,
        metadata: metadata,
        created_at: System.system_time(:second)
      })

    case result do
      {:ok, _event} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp acquire_write_lock(repo) do
    case SQL.query(repo, "SELECT pg_advisory_xact_lock($1)", [@write_lock]) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp acquire_registration_lock(repo) do
    case SQL.query(repo, "SELECT pg_advisory_xact_lock($1)", [@registration_lock]) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp enforce_registration_limits(repo, since, address, address_limit, global_limit) do
    with :ok <- enforce_address_registration_limit(repo, since, address, address_limit) do
      enforce_global_registration_limit(repo, since, global_limit)
    end
  end

  defp enforce_address_registration_limit(_repo, _since, nil, _limit), do: :ok

  defp enforce_address_registration_limit(repo, since, address, limit) do
    count =
      repo.aggregate(
        from(registration in Registration,
          where:
            registration.created_at >= ^since and
              registration.registration_address == ^address
        ),
        :count
      )

    allow_registration_count(count, limit)
  end

  defp enforce_global_registration_limit(repo, since, limit) do
    count =
      repo.aggregate(
        from(registration in Registration, where: registration.created_at >= ^since),
        :count
      )

    allow_registration_count(count, limit)
  end

  defp allow_registration_count(count, limit) when count < limit, do: :ok
  defp allow_registration_count(_count, _limit), do: {:error, :rate_limited}

  defp insert_registration(repo, registration) do
    with {:ok, _record} <- repo.insert(struct(Registration, registration)),
         :ok <-
           insert_agent_event(repo, registration.id, "registration.created", %{
             registration_type: registration.registration_type,
             network_address: registration.registration_address
           }),
         :ok <-
           insert_agent_event(repo, registration.id, "claim.requested", %{
             email: registration.claim_email
           }),
         :ok <- insert_agent_event(repo, registration.id, "user_code.minted", %{}) do
      {:ok, registration}
    end
  end

  defp transaction(repo, callback) do
    result =
      repo.transaction(fn ->
        case callback.() do
          {:ok, value} -> {:value, value}
          :ok -> :ok
          {:error, reason} -> repo.rollback(reason)
        end
      end)

    case result do
      {:ok, {:value, value}} -> {:ok, value}
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp limit(opts),
    do: opts |> Keyword.get(:limit) |> positive_integer(@default_limit) |> min(@maximum_limit)

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default
end
