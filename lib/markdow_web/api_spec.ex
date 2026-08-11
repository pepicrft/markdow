defmodule MarkdowWeb.ApiSpec do
  @moduledoc "The OpenAPI document for every supported Markdow operation."

  @behaviour OpenApiSpex.OpenApi

  alias MarkdowWeb.Router
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}

  @impl true
  def spec do
    %OpenApi{
      info: %Info{
        title: "Markdow note interface",
        version: "0.1.0",
        description:
          "Manage users, isolated Markdown vaults, notes, and bring-your-own embedding credentials through a headless service."
      },
      servers: [%Server{url: MarkdowWeb.PublicOrigin.default()}],
      components: %Components{
        securitySchemes: %{
          "bearerAuth" => %SecurityScheme{type: "http", scheme: "bearer"}
        }
      },
      security: [%{"bearerAuth" => []}],
      paths: Paths.from_router(Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
