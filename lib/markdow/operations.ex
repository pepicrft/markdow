defmodule Markdow.Operations do
  @moduledoc """
  The shared operation catalog for the Hypertext Transfer Protocol and Model Context
  Protocol interfaces.

  Requests from either interface pass through `call/3`, which keeps behavior and
  response shapes aligned.
  """

  alias Markdow.Accounts
  alias Markdow.AgentAuth
  alias Markdow.Embeddings
  alias Markdow.Index

  @spec all() :: [map()]
  def all do
    [
      %{
        name: "health",
        description: "Check that Markdow and its PostgreSQL index are ready.",
        scope: nil,
        inputSchema: object_schema(),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "list_users",
        description: "List the people who own Markdow vaults.",
        scope: "users:read",
        inputSchema: object_schema(),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "get_user",
        description: "Read one user.",
        scope: "users:read",
        inputSchema: object_schema(%{"id" => string_schema()}, ["id"]),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "create_user",
        description: "Create a user who can own one or more vaults.",
        scope: "users:write",
        inputSchema:
          object_schema(
            %{"id" => string_schema(), "email" => string_schema(), "name" => string_schema()},
            [
              "email"
            ]
          ),
        annotations: %{idempotentHint: false}
      },
      %{
        name: "revoke_agent_credentials",
        description: "Revoke every agent access token belonging to one user.",
        scope: "users:write",
        inputSchema: object_schema(%{"user_id" => string_schema()}, ["user_id"]),
        annotations: %{destructiveHint: true, idempotentHint: true}
      },
      %{
        name: "list_vaults",
        description: "List the vaults owned by one user.",
        scope: "vaults:read",
        inputSchema: object_schema(%{"user_id" => string_schema()}, ["user_id"]),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "get_vault",
        description: "Read one vault and its owner.",
        scope: "vaults:read",
        inputSchema: object_schema(%{"id" => string_schema()}, ["id"]),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "create_vault",
        description: "Create a vault for one user.",
        scope: "vaults:write",
        inputSchema:
          object_schema(
            %{
              "id" => string_schema(),
              "user_id" => string_schema(),
              "name" => string_schema()
            },
            ["user_id", "name"]
          ),
        annotations: %{idempotentHint: false}
      },
      %{
        name: "list_notes",
        description: "List indexed notes in path order with pagination.",
        scope: "notes:read",
        inputSchema:
          object_schema(
            %{
              "vault_id" => string_schema(),
              "limit" => integer_schema(1, 100),
              "offset" => integer_schema(0, nil)
            },
            ["vault_id"]
          ),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "get_note",
        description: "Read one note with its original Markdown body and indexed metadata.",
        scope: "notes:read",
        inputSchema:
          object_schema(%{"vault_id" => string_schema(), "id" => string_schema()}, [
            "vault_id",
            "id"
          ]),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "create_note",
        description: "Create a Markdown note and index its metadata, tags, and wikilinks.",
        scope: "notes:write",
        inputSchema: note_input_schema(false),
        annotations: %{idempotentHint: false}
      },
      %{
        name: "update_note",
        description: "Replace an existing Markdown note and refresh its index records.",
        scope: "notes:write",
        inputSchema: note_input_schema(true),
        annotations: %{idempotentHint: true}
      },
      %{
        name: "delete_note",
        description: "Delete a note from content storage and the PostgreSQL index.",
        scope: "notes:write",
        inputSchema:
          object_schema(%{"vault_id" => string_schema(), "id" => string_schema()}, [
            "vault_id",
            "id"
          ]),
        annotations: %{destructiveHint: true}
      },
      %{
        name: "search_notes",
        description: "Search note titles and bodies with PostgreSQL full-text search.",
        scope: "notes:read",
        inputSchema:
          object_schema(
            %{
              "vault_id" => string_schema(),
              "q" => string_schema(),
              "limit" => integer_schema(1, 100)
            },
            ["vault_id", "q"]
          ),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "list_backlinks",
        description: "List notes that link to the requested note with surrounding context.",
        scope: "notes:read",
        inputSchema:
          object_schema(%{"vault_id" => string_schema(), "id" => string_schema()}, [
            "vault_id",
            "id"
          ]),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "get_note_graph",
        description: "Return linked notes and edges up to three hops from a note.",
        scope: "notes:read",
        inputSchema:
          object_schema(
            %{
              "vault_id" => string_schema(),
              "id" => string_schema(),
              "depth" => integer_schema(1, 3)
            },
            ["vault_id", "id"]
          ),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "import_note",
        description: "Import a Markdown file as a note.",
        scope: "notes:write",
        inputSchema:
          object_schema(
            %{
              "vault_id" => string_schema(),
              "filename" => string_schema(),
              "body" => string_schema()
            },
            ["vault_id", "filename", "body"]
          ),
        annotations: %{idempotentHint: false}
      },
      %{
        name: "rebuild_index",
        description: "Rebuild the complete PostgreSQL index from content storage.",
        scope: "notes:write",
        inputSchema: object_schema(%{"vault_id" => string_schema()}, ["vault_id"]),
        annotations: %{destructiveHint: false, idempotentHint: true}
      },
      %{
        name: "list_documents",
        description:
          "List every path in a vault, including indexed Markdown notes and byte-preserved attachments.",
        scope: "documents:read",
        inputSchema: object_schema(%{"vault_id" => string_schema()}, ["vault_id"]),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "read_document",
        description:
          "Read a Markdown note or attachment as Base64 while preserving its relative path and media type.",
        scope: "documents:read",
        inputSchema:
          object_schema(
            %{"vault_id" => string_schema(), "path" => string_schema()},
            ["vault_id", "path"]
          ),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "write_document",
        description:
          "Create or replace a path-preserving document. Markdown is indexed; other bytes are preserved unchanged.",
        scope: "documents:write",
        inputSchema:
          object_schema(
            %{
              "vault_id" => string_schema(),
              "path" => string_schema(),
              "data_base64" => string_schema()
            },
            ["vault_id", "path", "data_base64"]
          ),
        annotations: %{idempotentHint: true}
      },
      %{
        name: "delete_document",
        description: "Delete a Markdown note or attachment by its vault-relative path.",
        scope: "documents:write",
        inputSchema:
          object_schema(
            %{"vault_id" => string_schema(), "path" => string_schema()},
            ["vault_id", "path"]
          ),
        annotations: %{destructiveHint: true, idempotentHint: true}
      },
      %{
        name: "get_embedding_configuration",
        description: "Read the redacted embedding configuration for an account.",
        scope: "embeddings:read",
        inputSchema: object_schema(%{"user_id" => string_schema()}, ["user_id"]),
        annotations: %{readOnlyHint: true}
      },
      %{
        name: "configure_embedding",
        description:
          "Configure the embeddings endpoint, model, and encrypted credential for an account. The endpoint must speak the OpenAI embeddings protocol over https and must not resolve to a private address. Nothing is stored until a real embedding request succeeds.",
        scope: "embeddings:write",
        inputSchema:
          object_schema(
            %{
              "user_id" => string_schema(),
              "endpoint" => string_schema(),
              "model" => string_schema(),
              "dimensions" => integer_schema(1, 10_000),
              "token" => string_schema()
            },
            ["user_id", "endpoint", "model", "token"]
          ),
        annotations: %{idempotentHint: true}
      },
      %{
        name: "validate_embedding_configuration",
        description:
          "Make a minimal embedding request to check an account's endpoint, model, and credential.",
        scope: "embeddings:write",
        inputSchema:
          object_schema(%{"user_id" => string_schema(), "token" => string_schema()}, [
            "user_id"
          ]),
        annotations: %{idempotentHint: true}
      },
      %{
        name: "embed_text",
        description:
          "Embed text for a vault using the configuration of the account that owns it.",
        scope: "embeddings:write",
        inputSchema:
          object_schema(
            %{
              "vault_id" => string_schema(),
              "input" => string_schema(),
              "token" => string_schema()
            },
            ["vault_id", "input"]
          ),
        annotations: %{idempotentHint: true}
      },
      %{
        name: "delete_embedding_configuration",
        description: "Delete an account's embedding configuration and encrypted credential.",
        scope: "embeddings:write",
        inputSchema: object_schema(%{"user_id" => string_schema()}, ["user_id"]),
        annotations: %{destructiveHint: true}
      }
    ]
  end

  @spec names() :: [String.t()]
  def names, do: Enum.map(all(), & &1.name)

  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(name), do: Enum.find_value(all(), :error, &if(&1.name == name, do: {:ok, &1}))

  @spec call(String.t(), map(), Index.Context.t()) :: {:ok, term()} | {:error, term()}
  def call(name, arguments, index \\ Index.context())

  def call("health", _arguments, index) do
    with :ok <- Index.health(index), do: {:ok, %{status: "ok"}}
  end

  def call("list_users", _arguments, index), do: Accounts.list_users(index.repo)

  def call("get_user", %{"id" => id}, index), do: Accounts.get_user(id, index.repo)

  def call("create_user", %{"email" => _email} = arguments, index),
    do: Accounts.create_user(arguments, index.repo)

  def call("revoke_agent_credentials", %{"user_id" => user_id}, index) do
    with {:ok, count} <- AgentAuth.revoke_user_access_tokens(user_id, index: index),
         do: {:ok, %{user_id: user_id, revoked: count}}
  end

  def call("list_vaults", %{"user_id" => user_id}, index),
    do: Accounts.list_vaults(user_id, index.repo)

  def call("get_vault", %{"id" => id}, index), do: Accounts.get_vault(id, index.repo)

  def call("create_vault", %{"user_id" => user_id, "name" => _name} = arguments, index),
    do: Accounts.create_vault(user_id, Map.delete(arguments, "user_id"), index.repo)

  def call("list_notes", %{"vault_id" => vault_id} = arguments, index) do
    Index.list_notes(index, vault_id,
      limit: integer_argument(arguments, "limit"),
      offset: integer_argument(arguments, "offset")
    )
  end

  def call("get_note", %{"vault_id" => vault_id, "id" => id}, index),
    do: Index.get_note(index, vault_id, id)

  def call("create_note", %{"vault_id" => vault_id, "body" => body} = arguments, index) do
    id = Map.get(arguments, "id") || note_id(arguments)
    Index.write_note(index, vault_id, id, body, note_options(arguments))
  end

  def call(
        "update_note",
        %{"vault_id" => vault_id, "id" => id, "body" => body} = arguments,
        index
      ) do
    with {:ok, _note} <- Index.get_note(index, vault_id, id) do
      Index.write_note(index, vault_id, id, body, note_options(arguments))
    end
  end

  def call("delete_note", %{"vault_id" => vault_id, "id" => id}, index) do
    with :ok <- Index.delete_note(index, vault_id, id),
         do: {:ok, %{vault_id: vault_id, id: id, deleted: true}}
  end

  def call("search_notes", %{"vault_id" => vault_id, "q" => query} = arguments, index) do
    Index.search(index, vault_id, query, limit: integer_argument(arguments, "limit"))
  end

  def call("list_backlinks", %{"vault_id" => vault_id, "id" => id}, index),
    do: Index.backlinks(index, vault_id, id)

  def call("get_note_graph", %{"vault_id" => vault_id, "id" => id} = arguments, index) do
    Index.graph(index, vault_id, id, depth: integer_argument(arguments, "depth"))
  end

  def call(
        "import_note",
        %{"vault_id" => vault_id, "filename" => filename, "body" => body},
        index
      ) do
    path =
      if String.downcase(Path.extname(filename)) == ".md", do: filename, else: filename <> ".md"

    with {:ok, document} <- Index.write_document(index, vault_id, path, body) do
      Index.get_note(index, vault_id, document.id)
    end
  end

  def call("rebuild_index", %{"vault_id" => vault_id}, index) do
    with :ok <- Index.rebuild!(index, vault_id), do: {:ok, %{status: "rebuilt"}}
  end

  def call("list_documents", %{"vault_id" => vault_id}, index),
    do: Index.list_documents(index, vault_id)

  def call("read_document", %{"vault_id" => vault_id, "path" => path}, index) do
    with {:ok, document} <- Index.read_document(index, vault_id, path) do
      {:ok, document |> Map.delete(:data) |> Map.put(:data_base64, Base.encode64(document.data))}
    end
  end

  def call(
        "write_document",
        %{"vault_id" => vault_id, "path" => path, "data_base64" => encoded},
        index
      ) do
    with {:ok, data} <- Base.decode64(encoded),
         {:ok, document} <- Index.write_document(index, vault_id, path, data) do
      {:ok, Map.delete(document, :data)}
    else
      :error -> {:error, :invalid_base64}
      error -> error
    end
  end

  def call("delete_document", %{"vault_id" => vault_id, "path" => path}, index) do
    with :ok <- Index.delete_document(index, vault_id, path),
         do: {:ok, %{vault_id: vault_id, path: path, deleted: true}}
  end

  def call("get_embedding_configuration", %{"user_id" => user_id}, index),
    do: Embeddings.get_configuration(index, user_id)

  def call(
        "configure_embedding",
        %{"user_id" => user_id, "token" => _token} = arguments,
        index
      ),
      do: Embeddings.put_configuration(index, user_id, Map.delete(arguments, "user_id"))

  def call("validate_embedding_configuration", %{"user_id" => user_id} = arguments, index),
    do: Embeddings.validate_configuration(index, user_id, Map.get(arguments, "token"))

  def call("embed_text", %{"vault_id" => vault_id, "input" => input} = arguments, index),
    do: Embeddings.embed(index, vault_id, input, Map.get(arguments, "token"))

  def call("delete_embedding_configuration", %{"user_id" => user_id}, index),
    do: Embeddings.delete_configuration(index, user_id)

  def call(name, _arguments, _index) when is_binary(name) do
    if name in names(), do: {:error, :invalid_arguments}, else: {:error, :unknown_operation}
  end

  @spec call(String.t(), map(), Index.Context.t(), map()) ::
          {:ok, term()} | {:error, term()}
  def call(name, arguments, index, authorization) when is_map(authorization) do
    with :ok <- authorize_arguments(name, arguments, index, authorization),
         {:ok, result} <- call(name, arguments, index) do
      scope_result(name, result, authorization)
    end
  end

  defp note_options(arguments) do
    [
      title: Map.get(arguments, "title"),
      path: normalize_note_path(Map.get(arguments, "path")),
      metadata: Map.get(arguments, "metadata", %{})
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp authorize_arguments(_name, _arguments, _index, %{kind: :api_key}), do: :ok

  defp authorize_arguments("health", _arguments, _index, %{kind: :access_token}), do: :ok

  defp authorize_arguments("list_users", _arguments, _index, %{kind: :access_token}), do: :ok

  defp authorize_arguments("get_user", %{"id" => id}, _index, authorization),
    do: authorize_user(id, authorization)

  defp authorize_arguments("create_user", _arguments, _index, %{kind: :access_token}),
    do: {:error, :forbidden}

  defp authorize_arguments(
         "revoke_agent_credentials",
         _arguments,
         _index,
         %{kind: :access_token}
       ),
       do: {:error, :forbidden}

  defp authorize_arguments("list_vaults", %{"user_id" => user_id}, _index, authorization),
    do: authorize_user(user_id, authorization)

  defp authorize_arguments(
         "create_vault",
         %{"user_id" => user_id},
         _index,
         authorization
       ),
       do: authorize_user(user_id, authorization)

  defp authorize_arguments("get_vault", %{"id" => vault_id}, index, authorization),
    do: authorize_vault(vault_id, index, authorization)

  defp authorize_arguments(_name, %{"user_id" => user_id}, _index, authorization),
    do: authorize_user(user_id, authorization)

  defp authorize_arguments(_name, %{"vault_id" => vault_id}, index, authorization),
    do: authorize_vault(vault_id, index, authorization)

  defp authorize_arguments(_name, _arguments, _index, %{kind: :access_token}),
    do: {:error, :forbidden}

  defp authorize_user(user_id, %{kind: :access_token, user_id: user_id}), do: :ok
  defp authorize_user(_user_id, %{kind: :access_token}), do: {:error, :forbidden}

  defp authorize_vault(vault_id, index, %{kind: :access_token, user_id: user_id}) do
    case Accounts.get_vault(vault_id, index.repo) do
      {:ok, %{user_id: ^user_id}} -> :ok
      {:ok, _vault} -> {:error, :forbidden}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp scope_result("list_users", users, %{kind: :access_token, user_id: user_id}),
    do: {:ok, Enum.filter(users, &(&1.id == user_id))}

  defp scope_result(_name, result, _authorization), do: {:ok, result}

  defp note_id(arguments) do
    arguments
    |> Map.get("path", Map.get(arguments, "title", "note-#{System.unique_integer([:positive])}"))
    |> Path.basename()
    |> normalize_note_path()
    |> slug()
  end

  defp normalize_note_path(nil), do: nil

  defp normalize_note_path(path) when is_binary(path) do
    extension = Path.extname(path)

    if String.downcase(extension) == ".md",
      do: Path.rootname(path, extension),
      else: path
  end

  defp slug(value) do
    slug =
      value
      |> String.downcase()
      |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
      |> String.trim("-")

    if slug == "", do: "note-#{System.unique_integer([:positive])}", else: slug
  end

  defp integer_argument(arguments, key) do
    case Map.get(arguments, key) do
      value when is_integer(value) -> value
      value when is_binary(value) -> parse_integer(value)
      _value -> nil
    end
  end

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _error -> nil
    end
  end

  defp note_input_schema(require_id) do
    required = if require_id, do: ["vault_id", "id", "body"], else: ["vault_id", "body"]

    object_schema(
      %{
        "vault_id" => string_schema(),
        "id" => string_schema(),
        "title" => string_schema(),
        "path" => string_schema(),
        "body" => string_schema(),
        "metadata" => %{type: "object", additionalProperties: true}
      },
      required
    )
  end

  defp object_schema(properties \\ %{}, required \\ []) do
    %{type: "object", properties: properties, required: required, additionalProperties: false}
  end

  defp string_schema, do: %{type: "string"}

  defp integer_schema(minimum, nil), do: %{type: "integer", minimum: minimum}

  defp integer_schema(minimum, maximum),
    do: %{type: "integer", minimum: minimum, maximum: maximum}
end
