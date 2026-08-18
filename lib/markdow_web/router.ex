defmodule MarkdowWeb.Router do
  use MarkdowWeb, :router

  pipeline :documented do
    plug :accepts, ["json"]
    plug MarkdowWeb.RateLimit, bucket: :api
    plug OpenApiSpex.Plug.PutApiSpec, module: MarkdowWeb.ApiSpec
  end

  pipeline :documented_page do
    plug MarkdowWeb.RateLimit, bucket: :marketing, response: :text
    plug OpenApiSpex.Plug.PutApiSpec, module: MarkdowWeb.ApiSpec
  end

  pipeline :documented_reference do
    plug MarkdowWeb.RateLimit, bucket: :documentation, response: :text
    plug OpenApiSpex.Plug.PutApiSpec, module: MarkdowWeb.ApiSpec
  end

  pipeline :json_api do
    plug :accepts, ["json"]
    plug MarkdowWeb.RateLimit, bucket: :authentication
  end

  pipeline :mcp do
    plug MarkdowWeb.RateLimit, bucket: :model_context_protocol
    plug MarkdowWeb.ValidateMcpOrigin
    plug MarkdowWeb.ApiAuth, scopes: ["mcp"]
  end

  pipeline :agent_claim do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MarkdowWeb.RateLimit, bucket: :authentication, response: :text
  end

  scope "/", MarkdowWeb do
    pipe_through :documented_page

    get "/", HomeController, :show
    get "/terms", LegalController, :terms
    get "/privacy", LegalController, :privacy
    get "/cookies", LegalController, :cookies
    get "/og-image", OpenGraphController, :show
  end

  scope "/", MarkdowWeb do
    pipe_through :documented_reference

    get "/docs", ApiReferenceController, :show
  end

  scope "/", MarkdowWeb do
    pipe_through :documented

    get "/health", HealthController, :show
    get "/users", UserController, :index
    post "/users", UserController, :create
    get "/users/:id", UserController, :show
    delete "/users/:user_id/agent-credentials", UserController, :revoke_agent_credentials
    get "/users/:user_id/vaults", VaultController, :index
    post "/users/:user_id/vaults", VaultController, :create
    get "/vaults/:id", VaultController, :show
    get "/vaults/:vault_id/notes", NoteController, :index
    post "/vaults/:vault_id/notes", NoteController, :create
    get "/vaults/:vault_id/notes/:id", NoteController, :show
    put "/vaults/:vault_id/notes/:id", NoteController, :update
    delete "/vaults/:vault_id/notes/:id", NoteController, :delete
    get "/vaults/:vault_id/search", SearchController, :search
    get "/vaults/:vault_id/notes/:id/backlinks", SearchController, :backlinks
    get "/vaults/:vault_id/notes/:id/graph", SearchController, :graph
    post "/vaults/:vault_id/notes/import", IndexController, :import
    post "/vaults/:vault_id/index/rebuild", IndexController, :rebuild
    get "/vaults/:vault_id/documents", DocumentController, :index
    get "/users/:user_id/embedding-configuration", EmbeddingController, :show
    put "/users/:user_id/embedding-configuration", EmbeddingController, :update

    post "/users/:user_id/embedding-configuration/validate",
         EmbeddingController,
         :validate

    delete "/users/:user_id/embedding-configuration", EmbeddingController, :delete
    post "/vaults/:vault_id/embeddings", EmbeddingController, :embed
  end

  scope "/", MarkdowWeb do
    pipe_through :documented

    get "/vaults/:vault_id/documents/*path", DocumentController, :show
    put "/vaults/:vault_id/documents/*path", DocumentController, :write
    delete "/vaults/:vault_id/documents/*path", DocumentController, :delete
  end

  scope "/", MarkdowWeb do
    pipe_through :documented

    get "/openapi.json", OpenApiController, :show
  end

  scope "/", MarkdowWeb do
    pipe_through :json_api

    get "/.well-known/oauth-protected-resource", DiscoveryController, :protected_resource

    get "/.well-known/oauth-protected-resource/mcp",
        DiscoveryController,
        :mcp_protected_resource

    get "/.well-known/oauth-authorization-server",
        DiscoveryController,
        :authorization_server

    get "/.well-known/jwks.json", DiscoveryController, :jwks
    get "/.well-known/mcp/server-card.json", DiscoveryController, :mcp_server_card
    post "/agent/identity", AgentIdentityController, :create
    post "/agent/identity/claim", AgentIdentityController, :claim
    post "/agent/event/notify", DiscoveryController, :event_notify
    post "/oauth2/token", OAuthController, :token
    post "/oauth2/revoke", OAuthController, :revoke
  end

  scope "/", MarkdowWeb do
    pipe_through :documented_reference

    get "/auth.md", AuthMarkdownController, :show
  end

  scope "/", MarkdowWeb do
    pipe_through :agent_claim

    get "/agent/identity/claim", ClaimController, :show
    post "/agent/identity/claim/sign-up", ClaimController, :sign_up
    post "/agent/identity/claim/sign-in", ClaimController, :sign_in
    get "/agent/identity/claim/verify-email", ClaimController, :show_email_verification
    post "/agent/identity/claim/verify-email", ClaimController, :verify_email

    post "/agent/identity/claim/resend-email-verification",
         ClaimController,
         :resend_email_verification

    post "/agent/identity/claim/confirm", ClaimController, :confirm
    post "/agent/identity/claim/sign-out", ClaimController, :sign_out
  end

  scope "/" do
    pipe_through :mcp

    forward "/mcp", Markdow.MCP
  end
end
