# Markdow

Markdow is a headless Markdown note service for editors and agents. A user can own multiple isolated vaults, and every note belongs to exactly one vault. Markdown files remain the content source of truth, while PostgreSQL provides full-text search, tags, backlinks, graph traversal, and authentication records shared by every cluster replica.

It exposes the same operations through an [OpenAPI](https://www.openapis.org/)-described application programming interface and a [Model Context Protocol](https://modelcontextprotocol.io/) server. Agent registration follows the [auth.md protocol](https://workos.com/auth-md). Vault owners can bring their own OpenAI provider token for embeddings; Markdow encrypts a stored token and never returns it from an interface.

## Run locally

Install the pinned Elixir and Erlang versions and run PostgreSQL locally. Mise gives every Git worktree a stable numeric development instance. It uses that instance to choose distinct server and test ports plus distinct development and test databases. This lets several worktrees run at the same time without sharing a listener or PostgreSQL state.

Create the database, run migrations, seed two users with three connected example vaults, and start the server:

```sh
mise install
mise exec -- mix setup
MARKDOW_API_KEY=development mise exec -- mix phx.server
```

Inspect this worktree's assigned values and keep its address in the current shell:

```sh
mise exec -- sh -c 'printf "server: %s\ndevelopment database: %s\ntest database: %s\n" "$MARKDOW_URL" "$MARKDOW_DATABASE_NAME" "$MARKDOW_TEST_DATABASE_NAME"'
MARKDOW_URL="$(mise exec -- printenv MARKDOW_URL)"
```

The assignment is persisted in Git's per-worktree metadata, so it survives new shells. A linked worktree receives another unused instance on its first Mise invocation. The server stores notes below `~/.markdow/vault` and stores its shared index in the worktree-specific PostgreSQL database. Existing installations use the `default` vault at the storage root. Additional vaults use `vaults/<vault-id>/` below that root.

Reset the development database and seed the users, vaults, and notes again:

```sh
mise exec -- mix ecto.reset
```

Check the service, list users and vaults, then list the seeded notes in the default vault:

```sh
curl "$MARKDOW_URL/health"
curl -H 'Authorization: Bearer development' "$MARKDOW_URL/users"
curl -H 'Authorization: Bearer development' "$MARKDOW_URL/users/local/vaults"
curl -H 'Authorization: Bearer development' "$MARKDOW_URL/vaults/default/notes"
```

The interactive Scalar reference is available at `$MARKDOW_URL/docs`, and its OpenAPI document is available at `$MARKDOW_URL/openapi.json`. Agent authentication starts at `$MARKDOW_URL/auth.md`, and the Model Context Protocol endpoint is `$MARKDOW_URL/mcp`.

An agent begins sign-up by posting the user's email as a `service_auth` login hint. Markdow gives the agent a short code and a Markdow-owned verification page. The user opens that page, signs in or creates a password-based account, and enters the code there. The resulting credential is bound to that user, accepted only by its intended resource, and denied access to every other user's vaults.

## Move an Obsidian vault

The document interface preserves vault-relative paths and filename case. A valid UTF-8 file whose name ends in `.md` becomes an indexed note. Every other file is stored byte-for-byte, so images, Portable Document Format files, audio, video, canvas data, stylesheets, and Obsidian configuration can travel with the vault.

The shared operations are `list_documents`, `read_document`, `write_document`, and `delete_document`. They are available both as [Model Context Protocol](https://modelcontextprotocol.io/) tools and through these Representational State Transfer application programming interface routes:

```text
GET    /vaults/:vault_id/documents
GET    /vaults/:vault_id/documents/*path
PUT    /vaults/:vault_id/documents/*path
DELETE /vaults/:vault_id/documents/*path
```

Reads and writes carry the original bytes as Base64 in `data_base64`. A single document may be up to 5 mebibytes. Directories, spaces, Unicode, apostrophes, and duplicate basenames in different directories are supported. Symbolic links and traversal paths are rejected rather than followed.

An agent can migrate a vault after following `/auth.md`: create a destination vault, walk the source directory, and call `write_document` for each approved regular file. Exclude `.git` and inspect `.obsidian` plugin data before uploading it, because those directories can contain repository history or third-party credentials. Markdow never needs them to index the notes themselves.

Configure and validate a vault's embedding provider with your own OpenAI application programming interface key:

```sh
curl -X PUT \
  -H 'Authorization: Bearer development' \
  -H 'Content-Type: application/json' \
  "$MARKDOW_URL/vaults/default/embedding-configuration" \
  -d '{"provider":"openai","model":"text-embedding-3-small","token":"'"$OPENAI_API_KEY"'"}'

curl -X POST \
  -H 'Authorization: Bearer development' \
  -H 'Content-Type: application/json' \
  "$MARKDOW_URL/vaults/default/embedding-configuration/validate" \
  -d '{}'
```

The validation request creates one small embedding and therefore incurs the provider's normal usage charge. `embed_text`, `configure_embedding`, `validate_embedding_configuration`, and their matching web routes use the same shared operation definitions.

## Configuration

Every setting has an environment variable for releases and containers:

- `MARKDOW_DATABASE_NAME`: development database name. Mise assigns a worktree-specific value.
- `MARKDOW_TEST_DATABASE_NAME`: test database name. Mise combines the test partition with the worktree instance.
- `MARKDOW_TEST_PORT`: test endpoint port. Mise assigns a worktree-specific value.
- `MARKDOW_DATABASE_URL`: required PostgreSQL connection address in production.
- `MARKDOW_DATABASE_SSL`: require encrypted database transport, default `true` in production.
- `MARKDOW_DATABASE_CERTIFICATE_AUTHORITY_FILE`: certificate authority file used to verify the PostgreSQL server.
- `MARKDOW_POOL_SIZE`: PostgreSQL connection pool size, default `10`.
- `MARKDOW_DATA_DIR`: local content data directory, default `~/.markdow`.
- `MARKDOW_STORAGE_PATH`: Markdown vault directory, default `~/.markdow/vault`.
- `MARKDOW_STORAGE_DRIVER`: content driver, currently `local`.
- `MARKDOW_API_KEY`: local owner and application key. Production requires at least 32 bytes.
- `MARKDOW_SECRET_KEY_BASE`: required production secret used to sign browser sessions. Generate one with `openssl rand -base64 64`.
- `MARKDOW_EMBEDDING_SECRET_KEY`: base64-encoded 32-byte key used to encrypt stored provider tokens. Generate one with `openssl rand -base64 32`. Embedding configuration is unavailable in production until this is set.
- `MARKDOW_PORT`: listening port. Mise assigns a worktree-specific value; outside Mise it defaults to `4000`.
- `MARKDOW_HOST`: public host used in discovery documents and required in production.
- `MARKDOW_SCHEME`: public scheme used in discovery documents, default `https` in production.
- `MARKDOW_URL_PORT`: public port used in discovery documents, default `443` with `https` and otherwise the listening port.
- `MARKDOW_SERVER`: set to `true` when starting a release.
- `MARKDOW_AGENT_AUTH_PRIVATE_KEY_PEM`: required production signing key in Privacy-Enhanced Mail format.
- `MARKDOW_AGENT_AUTH_ALLOW_EPHEMERAL_KEY`: allow a process-local signing key. The default is `true` for local use and `false` in production.
- `MARKDOW_AGENT_AUTH_ADDRESS_LIMIT`: maximum registrations from one network address per hour, default `10`.
- `MARKDOW_AGENT_AUTH_GLOBAL_LIMIT`: maximum registrations across the deployment per hour, default `100`.
- `MARKDOW_AGENT_AUTH_CLAIM_ATTEMPT_LIMIT`: maximum confirmation-code attempts, default `5`.
- `MARKDOW_AGENT_AUTH_SIGN_IN_ATTEMPT_LIMIT`: maximum failed account sign-ins for one claim, default `10`.
- `MARKDOW_MARKETING_ROUTES`: set to `false` to disable `/`, `/terms`, `/privacy`, and `/cookies` for a self-hosted deployment. Operational routes such as `/docs`, `/health`, `/openapi.json`, `/auth.md`, and `/mcp` remain enabled.
- `MARKDOW_LEGAL_OPERATOR_NAME`, `MARKDOW_LEGAL_OPERATOR_ADDRESS`, and `MARKDOW_LEGAL_CONTACT_EMAIL`: required in production when marketing routes are enabled.
- `MARKDOW_LEGAL_REGISTRATION` and `MARKDOW_LEGAL_TAX_IDENTIFIER`: optional provider details when they apply.
- `MARKDOW_RATE_LIMIT_WINDOW_MS`: Hammer window length, default `60000` milliseconds.
- `MARKDOW_RATE_LIMIT_MARKETING`, `MARKDOW_RATE_LIMIT_DOCUMENTATION`, `MARKDOW_RATE_LIMIT_API`, `MARKDOW_RATE_LIMIT_AUTHENTICATION`, and `MARKDOW_RATE_LIMIT_MCP`: per-client request limits for each interface group.
- `MARKDOW_ALLOWED_MCP_ORIGINS`: comma-separated browser origins allowed to call the Model Context Protocol endpoint. Non-browser clients that send no `Origin` header remain supported. Set this to each self-hosted client origin.
- `MARKDOW_SMTP_RELAY` and `MARKDOW_SMTP_PORT`: Simple Mail Transfer Protocol relay used for email verification in production.
- `MARKDOW_EMAIL_FROM_NAME` and `MARKDOW_EMAIL_FROM_ADDRESS`: sender identity for verification messages.
- `SMOLANALYTICS_HOST` and `SMOLANALYTICS_WRITE_KEY`: optional anonymous browser analytics for the public marketing page. Both values are required to enable it.

General request limits use [Hammer](https://hexdocs.pm/hammer/readme.html) with a per-instance sliding window. Agent registration limits, confirmation-code attempts, and sign-in attempts are additionally stored in PostgreSQL, so those security budgets are shared across every replica. Deployments with several replicas should still enforce a shared general limit at the load balancer or replace the local Hammer backend with a distributed backend.

## Public pages and legal configuration

The built-in terms, privacy, and cookie pages are deliberately short. When configured, the marketing page runs [smolanalytics](https://github.com/Arjun0606/smolanalytics) in anonymous mode without browser storage. Otherwise it sets no cookies and runs no analytics. The interactive documentation loads its pinned Scalar client from jsDelivr with credential persistence, telemetry, and the optional agent disabled.

The production release refuses to enable marketing pages until the operator name, postal address, and contact email are configured. These templates are a practical starting point, not individualized legal advice. The operator remains responsible for updating infrastructure recipients, international transfers, retention periods, registration details, and any jurisdiction-specific requirements before publishing.

## Verification

Run the complete local checks with:

```sh
mise exec -- mix precommit
```

Build a release with:

```sh
mise exec -- mix release
MARKDOW_DATABASE_URL=ecto://user:password@database/markdow \
MARKDOW_DATABASE_SSL=false \
MARKDOW_API_KEY=replace-with-at-least-32-random-bytes \
MARKDOW_AGENT_AUTH_PRIVATE_KEY_PEM="$(cat private.pem)" \
MARKDOW_HOST=markdow.org \
_build/prod/rel/markdow/bin/markdow eval 'Markdow.Release.migrate()'

MARKDOW_SERVER=true \
MARKDOW_DATABASE_URL=ecto://user:password@database/markdow \
MARKDOW_DATABASE_SSL=false \
MARKDOW_API_KEY=replace-with-at-least-32-random-bytes \
MARKDOW_AGENT_AUTH_PRIVATE_KEY_PEM="$(cat private.pem)" \
MARKDOW_HOST=markdow.org \
_build/prod/rel/markdow/bin/markdow start
```

## Production deployment

The chart in `deploy/helm/markdow` provisions the application, a CloudNativePG PostgreSQL cluster, database backups, persistent document storage, external secrets, and the public ingress. `deploy/values-production.yaml` contains the Pepicrft cluster values. The `main` image is published only after checks pass, and Flux reconciles its immutable digest from the infrastructure repository.

Before the first reconciliation, create the following fields below the `markdow` item in the production secret store: `SECRET_KEY_BASE`, `API_KEY`, `AGENT_AUTH_PRIVATE_KEY_PEM`, `EMBEDDING_SECRET_KEY`, `POSTGRES_PASSWORD`, `LEGAL_OPERATOR_NAME`, `LEGAL_OPERATOR_ADDRESS`, and `LEGAL_CONTACT_EMAIL`. The document volume is included in the daily Velero filesystem backup, while PostgreSQL uses its own continuous backup.
