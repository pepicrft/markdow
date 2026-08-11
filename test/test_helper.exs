ExUnit.start(max_cases: 10)

Ecto.Adapters.SQL.Sandbox.mode(Markdow.Repo, :manual)
Mimic.copy(Markdow.Index)
Mimic.copy(Markdow.Embeddings.OpenAI)
Mimic.copy(Markdow.Accounts.EmailNotifier)
Mimic.copy(Markdow.RateLimit)
Mimic.copy(Finch)
