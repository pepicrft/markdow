# Markdow development instructions

## Tenancy and authentication

- Markdow is a multi-tenant service. Authorization must always derive from the
  individual authenticated user and the vault they own. Do not introduce a
  deployment-wide master token, shared user credential, or global secret that
  substitutes for user authorization.
- Browser authentication uses one-time email links. Store only a hash of each
  link token, expire and consume it after use, and bind any issued access token
  to the authenticated user.

## Writing

- Avoid acronyms. When one is necessary, include its full name and a link to a website that explains the concept.

## Elixir

- Minimize explicit raising patterns and raising function variants. Prefer pattern matching on tagged return values and function heads so invalid states fail where they are introduced.
- Use Elixir's standard `JSON` module for JavaScript Object Notation encoding and decoding. Do not add or use Jason in application or test code.

## Tests

- Never modify global state from a test. This includes application environment changes such as `Application.put_env/3`.
- Pass configuration and dependencies directly to the code under test.
- Every Elixir test module must run with `async: true`.

## Worktrees

- Run development and test commands through `mise exec --`. Mise assigns every Git worktree a stable development instance, server port, test port, development database, and test database.
- Do not hardcode local ports or database names in application code, tests, documentation, or agent instructions. Read the generated `MARKDOW_*` environment variables or derive public addresses from `MarkdowWeb.Endpoint`.

## Interface consistency

- Markdow is primarily a headless service. Keep its [Representational State Transfer](https://developer.mozilla.org/en-US/docs/Glossary/REST) application programming interface, [Model Context Protocol](https://modelcontextprotocol.io/) server, and [auth.md agent registration](https://workos.com/auth-md) workflow consistent.
- Describe every [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) operation with [OpenAPI](https://www.openapis.org/) through [OpenApiSpex](https://github.com/open-api-spex/open_api_spex).
- Use the same operation names, request fields, response fields, authorization scopes, and behavior in the OpenAPI operation identifiers and Model Context Protocol tool names.
- When an operation changes, update and test the Hypertext Transfer Protocol route, OpenAPI document, and Model Context Protocol tool together.
- Treat embedding provider tokens as secrets. Encrypt stored tokens, allow a one-request override, redact them from every response, and validate provider configuration through the same shared operation catalog.
- Keep `priv/repo/seeds.exs` representative of multiple users and vaults. End-to-end verification must seed them, prove that notes, search, links, and graphs remain isolated by vault with `curl`, and ask Codex in non-interactive mode to perform the same work through the Model Context Protocol server.

## GitHub pull requests

- Do not use em dashes in comments or reviews.
- Write comments and reviews as if Pepicrft wrote them directly. Do not frame them as assistant output unless explicitly requested.
- Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) for pull request titles in the form `type(markdow): summary`.
- Structure descriptions with the applicable headings `## What changed`, `## Why`, `## Root cause`, `## Approach`, `## Impact`, and `## Validation`.
- Use concise prose. Bullets are appropriate for concrete changes and validation, but the whole description should not be a terse file list.

## Web application verification

- Run the application locally and verify behavior with [headless Chrome](https://developer.chrome.com/docs/chromium/headless).
- Capture screenshots during verification.
- Include verification screenshots in the [GitHub pull request](https://docs.github.com/en/pull-requests) description. For fixes, include before and after screenshots.
