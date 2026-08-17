defmodule MarkdowWeb.ApiSchemas.NoteSummary do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "NoteSummary",
      type: :object,
      properties: %{
        vault_id: %OpenApiSpex.Schema{type: :string},
        id: %OpenApiSpex.Schema{type: :string},
        title: %OpenApiSpex.Schema{type: :string},
        path: %OpenApiSpex.Schema{type: :string},
        metadata: %OpenApiSpex.Schema{type: :object, additionalProperties: true},
        created_at: %OpenApiSpex.Schema{type: :string},
        updated_at: %OpenApiSpex.Schema{type: :string}
      },
      required: [:vault_id, :id, :title, :path, :metadata, :created_at, :updated_at]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.Note do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Note",
      allOf: [
        MarkdowWeb.ApiSchemas.NoteSummary,
        %OpenApiSpex.Schema{
          type: :object,
          properties: %{
            body: %OpenApiSpex.Schema{type: :string},
            tags: %OpenApiSpex.Schema{
              type: :array,
              items: %OpenApiSpex.Schema{type: :string}
            },
            links: %OpenApiSpex.Schema{
              type: :array,
              items: %OpenApiSpex.Schema{type: :object}
            }
          },
          required: [:body, :tags, :links]
        }
      ]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.NoteInput do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "NoteInput",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string},
        title: %OpenApiSpex.Schema{type: :string},
        path: %OpenApiSpex.Schema{type: :string},
        body: %OpenApiSpex.Schema{type: :string},
        metadata: %OpenApiSpex.Schema{type: :object, additionalProperties: true}
      },
      required: [:body],
      additionalProperties: false
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.ImportInput do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "ImportInput",
      type: :object,
      properties: %{
        filename: %OpenApiSpex.Schema{type: :string},
        body: %OpenApiSpex.Schema{type: :string}
      },
      required: [:filename, :body],
      additionalProperties: false
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.DeletedNote do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "DeletedNote",
      type: :object,
      properties: %{
        vault_id: %OpenApiSpex.Schema{type: :string},
        id: %OpenApiSpex.Schema{type: :string},
        deleted: %OpenApiSpex.Schema{type: :boolean}
      },
      required: [:vault_id, :id, :deleted]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.NoteList do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "NoteList",
      type: :object,
      properties: %{
        data: %OpenApiSpex.Schema{type: :array, items: MarkdowWeb.ApiSchemas.NoteSummary},
        pagination: %OpenApiSpex.Schema{
          type: :object,
          properties: %{
            limit: %OpenApiSpex.Schema{type: :integer},
            offset: %OpenApiSpex.Schema{type: :integer},
            total: %OpenApiSpex.Schema{type: :integer}
          },
          required: [:limit, :offset, :total]
        }
      },
      required: [:data, :pagination]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.SearchResult do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "SearchResult",
      allOf: [
        MarkdowWeb.ApiSchemas.NoteSummary,
        %OpenApiSpex.Schema{
          type: :object,
          properties: %{
            snippet: %OpenApiSpex.Schema{type: :string},
            rank: %OpenApiSpex.Schema{type: :number}
          },
          required: [:snippet, :rank]
        }
      ]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.Backlink do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Backlink",
      allOf: [
        MarkdowWeb.ApiSchemas.NoteSummary,
        %OpenApiSpex.Schema{
          type: :object,
          properties: %{context: %OpenApiSpex.Schema{type: :string}},
          required: [:context]
        }
      ]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.Graph do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Graph",
      type: :object,
      properties: %{
        vault_id: %OpenApiSpex.Schema{type: :string},
        root_id: %OpenApiSpex.Schema{type: :string},
        depth: %OpenApiSpex.Schema{type: :integer},
        nodes: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :object}},
        edges: %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :object}}
      },
      required: [:vault_id, :root_id, :depth, :nodes, :edges]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.User do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "User",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string},
        email: %OpenApiSpex.Schema{type: :string, format: :email},
        name: %OpenApiSpex.Schema{type: :string, nullable: true},
        email_verified_at: %OpenApiSpex.Schema{type: :string, nullable: true},
        created_at: %OpenApiSpex.Schema{type: :string},
        updated_at: %OpenApiSpex.Schema{type: :string}
      },
      required: [:id, :email, :email_verified_at, :created_at, :updated_at]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.Document do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Document",
      type: :object,
      properties: %{
        vault_id: %OpenApiSpex.Schema{type: :string},
        id: %OpenApiSpex.Schema{type: :string, nullable: true},
        path: %OpenApiSpex.Schema{type: :string},
        kind: %OpenApiSpex.Schema{type: :string, enum: ["note", "asset"]},
        media_type: %OpenApiSpex.Schema{type: :string},
        size: %OpenApiSpex.Schema{type: :integer, nullable: true},
        updated_at: %OpenApiSpex.Schema{type: :string, nullable: true}
      },
      required: [:path, :kind, :media_type]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.DeletedDocument do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "DeletedDocument",
      type: :object,
      properties: %{
        vault_id: %OpenApiSpex.Schema{type: :string},
        path: %OpenApiSpex.Schema{type: :string},
        deleted: %OpenApiSpex.Schema{type: :boolean}
      },
      required: [:vault_id, :path, :deleted]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.DocumentContent do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "DocumentContent",
      allOf: [
        MarkdowWeb.ApiSchemas.Document,
        %OpenApiSpex.Schema{
          type: :object,
          properties: %{data_base64: %OpenApiSpex.Schema{type: :string, format: :byte}},
          required: [:data_base64]
        }
      ]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.UserInput do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "UserInput",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string},
        email: %OpenApiSpex.Schema{type: :string, format: :email},
        name: %OpenApiSpex.Schema{type: :string}
      },
      required: [:email],
      additionalProperties: false
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.Vault do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Vault",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string},
        user_id: %OpenApiSpex.Schema{type: :string},
        name: %OpenApiSpex.Schema{type: :string},
        storage_prefix: %OpenApiSpex.Schema{type: :string},
        created_at: %OpenApiSpex.Schema{type: :string},
        updated_at: %OpenApiSpex.Schema{type: :string}
      },
      required: [:id, :user_id, :name, :storage_prefix, :created_at, :updated_at]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.VaultInput do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "VaultInput",
      type: :object,
      properties: %{
        id: %OpenApiSpex.Schema{type: :string},
        name: %OpenApiSpex.Schema{type: :string}
      },
      required: [:name],
      additionalProperties: false
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.EmbeddingConfiguration do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "EmbeddingConfiguration",
      type: :object,
      properties: %{
        user_id: %OpenApiSpex.Schema{type: :string},
        endpoint: %OpenApiSpex.Schema{type: :string},
        model: %OpenApiSpex.Schema{type: :string},
        dimensions: %OpenApiSpex.Schema{type: :integer, nullable: true},
        credential_hint: %OpenApiSpex.Schema{type: :string},
        validated_at: %OpenApiSpex.Schema{type: :string, nullable: true},
        created_at: %OpenApiSpex.Schema{type: :string},
        updated_at: %OpenApiSpex.Schema{type: :string}
      },
      required: [
        :user_id,
        :endpoint,
        :model,
        :credential_hint,
        :created_at,
        :updated_at
      ]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.EmbeddingConfigurationInput do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "EmbeddingConfigurationInput",
      type: :object,
      properties: %{
        endpoint: %OpenApiSpex.Schema{
          type: :string,
          description:
            "An endpoint speaking the OpenAI embeddings protocol. Must use https and must not resolve to a private or loopback address.",
          example: "https://api.openai.com/v1/embeddings"
        },
        model: %OpenApiSpex.Schema{type: :string, example: "text-embedding-3-small"},
        dimensions: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 10_000},
        token: %OpenApiSpex.Schema{type: :string, format: :password, writeOnly: true}
      },
      required: [:endpoint, :model, :token],
      additionalProperties: false
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.EmbeddingValidationInput do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "EmbeddingValidationInput",
      type: :object,
      properties: %{
        token: %OpenApiSpex.Schema{type: :string, format: :password, writeOnly: true}
      },
      additionalProperties: false
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.EmbeddingValidation do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "EmbeddingValidation",
      type: :object,
      properties: %{
        status: %OpenApiSpex.Schema{type: :string},
        user_id: %OpenApiSpex.Schema{type: :string},
        endpoint: %OpenApiSpex.Schema{type: :string},
        model: %OpenApiSpex.Schema{type: :string},
        dimensions: %OpenApiSpex.Schema{type: :integer}
      },
      required: [:status, :user_id, :endpoint, :model, :dimensions]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.EmbeddingInput do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "EmbeddingInput",
      type: :object,
      properties: %{
        input: %OpenApiSpex.Schema{type: :string},
        token: %OpenApiSpex.Schema{type: :string, format: :password, writeOnly: true}
      },
      required: [:input],
      additionalProperties: false
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.EmbeddingResult do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "EmbeddingResult",
      type: :object,
      properties: %{
        vault_id: %OpenApiSpex.Schema{type: :string},
        user_id: %OpenApiSpex.Schema{type: :string},
        endpoint: %OpenApiSpex.Schema{type: :string},
        model: %OpenApiSpex.Schema{type: :string},
        embedding: %OpenApiSpex.Schema{
          type: :array,
          items: %OpenApiSpex.Schema{type: :number}
        },
        dimensions: %OpenApiSpex.Schema{type: :integer},
        usage: %OpenApiSpex.Schema{type: :object, additionalProperties: true}
      },
      required: [:vault_id, :user_id, :endpoint, :model, :embedding, :dimensions, :usage]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.DeletedEmbeddingConfiguration do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "DeletedEmbeddingConfiguration",
      type: :object,
      properties: %{
        user_id: %OpenApiSpex.Schema{type: :string},
        deleted: %OpenApiSpex.Schema{type: :boolean}
      },
      required: [:user_id, :deleted]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.Status do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Status",
      type: :object,
      properties: %{status: %OpenApiSpex.Schema{type: :string}},
      required: [:status]
    },
    derive?: false
  )
end

defmodule MarkdowWeb.ApiSchemas.Error do
  @moduledoc false

  require OpenApiSpex

  OpenApiSpex.schema(
    %{
      title: "Error",
      type: :object,
      properties: %{error: %OpenApiSpex.Schema{type: :string}},
      required: [:error]
    },
    derive?: false
  )
end
