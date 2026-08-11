alias Markdow.Accounts
alias Markdow.Index

index = Index.context()

ensure_user = fn id, email, name ->
  case Accounts.get_user(id, index.repo) do
    {:ok, user} -> {:ok, user}
    {:error, :not_found} -> Accounts.create_user(%{"id" => id, "email" => email, "name" => name})
  end
end

ensure_vault = fn user_id, id, name ->
  case Accounts.get_vault(id, index.repo) do
    {:ok, vault} -> {:ok, vault}
    {:error, :not_found} -> Accounts.create_vault(user_id, %{"id" => id, "name" => name})
  end
end

{:ok, owner} = Accounts.get_user(Accounts.default_user_id(), index.repo)
{:ok, _default_vault} = Accounts.get_vault(Accounts.default_vault_id(), index.repo)
{:ok, research_vault} = ensure_vault.(owner.id, "research", "Research")
{:ok, collaborator} = ensure_user.("ada", "ada@example.com", "Ada")
{:ok, collaborator_vault} = ensure_vault.(collaborator.id, "ada-notes", "Ada's notes")

notes = [
  {"default", "welcome",
   """
   ---
   title: Welcome to Markdow
   tags: [markdow, inbox]
   ---
   # Welcome to Markdow

   This vault is ready for a headless note workflow. Start with [[Architecture]] and turn the open work in [[Project plan]] into linked notes.
   """, [path: "inbox/welcome"]},
  {"default", "architecture",
   """
   ---
   title: Architecture
   tags:
     - markdow
     - engineering
   ---
   # Architecture

   Markdown files are the content source of truth. PostgreSQL provides full-text search, tags, backlinks, and graph traversal. See [[Welcome to Markdow]] for the vault entry point.
   """, [path: "projects/markdow/architecture"]},
  {"default", "project-plan",
   """
   ---
   title: Project plan
   tags: [markdow, planning]
   ---
   # Project plan

   - [x] Boot the Elixir supervision tree.
   - [x] Index [[Architecture]].
   - [ ] Connect an editor through the Model Context Protocol server.
   - [ ] Capture working notes in [[Daily note]].
   """, [path: "projects/markdow/project-plan"]},
  {"default", "daily-note",
   """
   ---
   title: Daily note
   tags: [daily, markdow]
   ---
   # Daily note

   Markdow is running. Review [[Project plan]] and keep architectural decisions linked to [[Architecture]].
   """, [path: "daily/first-run"]},
  {research_vault.id, "welcome",
   """
   ---
   title: Research inbox
   tags: [research, inbox]
   ---
   # Research inbox

   A separate vault can reuse note identifiers without sharing search results or links. Continue with [[Reading list]].
   """, [path: "inbox/welcome"]},
  {research_vault.id, "reading-list",
   """
   ---
   title: Reading list
   tags: [research]
   ---
   # Reading list

   Summarize durable ideas in [[Research inbox]].
   """, [path: "library/reading-list"]},
  {collaborator_vault.id, "welcome",
   """
   ---
   title: Ada's private welcome
   tags: [inbox]
   ---
   # Ada's private welcome

   This note belongs to Ada's vault and remains isolated from the owner's vaults.
   """, [path: "inbox/welcome"]}
]

results =
  Enum.map(notes, fn {vault_id, id, body, opts} ->
    {{vault_id, id}, Index.write_note(index, vault_id, id, body, opts)}
  end)

documents = [
  {"attachments/readme.txt", "Attachments retain their original relative path and bytes.\n"},
  {"attachments/pixel.png",
   Base.decode64!(
     "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
   )}
]

document_results =
  Enum.map(documents, fn {path, data} ->
    {path, Index.write_document(index, "default", path, data)}
  end)

failures =
  Enum.filter(results ++ document_results, fn {_key, result} ->
    match?({:error, _reason}, result)
  end)

case failures do
  [] ->
    IO.puts(
      "Seeded #{length(results)} linked notes and #{length(document_results)} attachments across 3 vaults owned by 2 users."
    )

  [{key, {:error, reason}} | _remaining] ->
    IO.puts(:stderr, "Could not seed #{inspect(key)}: #{inspect(reason)}")
end
