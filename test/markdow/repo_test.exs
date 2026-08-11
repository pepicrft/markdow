defmodule Markdow.RepoTest do
  use Markdow.DataCase, async: true

  alias Ecto.Adapters.SQL
  alias Markdow.Index
  alias Markdow.Repo

  test "uses PostgreSQL and maintains the generated search index", %{index: index} do
    assert Repo.__adapter__() == Ecto.Adapters.Postgres

    assert {:ok, _note} =
             Index.write_note(
               index,
               "repo-search",
               "# Repository search\n\nA phosphorescent phrase."
             )

    assert {:ok, %{rows: [["tsvector", true]]}} =
             SQL.query(
               Repo,
               """
               SELECT pg_typeof(search_vector)::text,
                      search_vector @@ websearch_to_tsquery('simple', $1)
               FROM notes
               WHERE id = $2
               """,
               ["phosphorescent", "repo-search"]
             )

    assert {:ok, %{rows: [["notes_search_vector_index"]]}} =
             SQL.query(
               Repo,
               "SELECT to_regclass('notes_search_vector_index')::text",
               []
             )
  end
end
