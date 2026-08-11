# Markdow 📝

Markdow is a headless Markdown note service for editors and agents. Markdown files remain the source of truth, while PostgreSQL provides search, tags, backlinks, and graph traversal.

## What it offers ✨

- Multiple isolated vaults for each user.
- The same operations through an [OpenAPI](https://www.openapis.org/)-described web interface and a [Model Context Protocol](https://modelcontextprotocol.io/) server.
- Agent registration through the [auth.md protocol](https://workos.com/auth-md).
- Encrypted OpenAI embedding provider tokens that are never returned by the service.
- Safe migration of complete Obsidian vaults, including attachments and configuration files.

## Run locally 🚀

Install [Mise](https://mise.jdx.dev/) and PostgreSQL, then run:

```sh
mise install
mise exec -- mix setup
MARKDOW_API_KEY=development mise exec -- mix phx.server
```

Mise assigns a stable address and database to each Git worktree. Print the address with:

```sh
mise exec -- printenv MARKDOW_URL
```

Useful routes include:

- `/docs` for the interactive reference.
- `/openapi.json` for the OpenAPI document.
- `/auth.md` for agent registration.
- `/mcp` for the Model Context Protocol server.
- `/health` for service health.

Reset and reseed the local database with:

```sh
mise exec -- mix ecto.reset
```

## Verify ✅

Run all local checks with:

```sh
mise exec -- mix precommit
```

## Deploy 🚢

The production image and Helm chart are published after the checks pass on `main`. The chart lives in `deploy/helm/markdow`, and the Pepicrft production values live in `deploy/values-production.yaml`.

Production configuration is read from `MARKDOW_*` environment variables. Required secrets include the database address, application key, signing key, and secret used to encrypt embedding provider tokens.
