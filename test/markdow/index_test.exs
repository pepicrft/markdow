defmodule Markdow.IndexTest do
  use Markdow.DataCase, async: true

  alias Markdow.Accounts
  alias Markdow.Index
  alias Markdow.Repo
  alias Markdow.Storage.LocalFs

  test "indexes content, tags, full-text search, backlinks, and linked graphs", %{index: index} do
    assert {:ok, target} =
             Index.write_note(
               index,
               "architecture",
               """
               ---
               title: Architecture
               tags: [engineering, markdow]
               ---
               # Architecture

               PostgreSQL is the searchable index.
               """
             )

    assert target.tags == ["engineering", "markdow"]

    assert {:ok, source} =
             Index.write_note(
               index,
               "project-plan",
               "# Project plan\n\nReview [[Architecture]] before implementation."
             )

    assert source.links == [
             %{
               target_id: "architecture",
               context: "Review [[Architecture]] before implementation."
             }
           ]

    assert {:ok, [search_result]} = Index.search(index, "searchable")
    assert search_result.id == "architecture"
    assert search_result.snippet =~ "searchable"

    assert {:ok, [backlink]} = Index.backlinks(index, "architecture")
    assert backlink.id == "project-plan"
    assert backlink.context =~ "Architecture"

    assert {:ok, graph} = Index.graph(index, "project-plan", depth: 2)
    assert Enum.map(graph.nodes, & &1.id) == ["project-plan", "architecture"]

    assert graph.edges == [
             %{
               source_id: "project-plan",
               target_id: "architecture",
               context: "Review [[Architecture]] before implementation."
             }
           ]
  end

  test "updates and deletes the file and index together", %{index: index, root: root} do
    assert {:ok, _note} = Index.write_note(index, "draft", "# Draft\n\nOld phrase")
    assert {:ok, note} = Index.write_note(index, "draft", "# Final\n\nNew phrase")
    assert note.title == "Final"
    assert {:ok, []} = Index.search(index, "Old")
    assert {:ok, [_result]} = Index.search(index, "New")
    assert File.read(Path.join(root, "vault/draft.md")) == {:ok, "# Final\n\nNew phrase"}

    assert :ok = Index.delete_note(index, "draft")
    assert Index.get_note(index, "draft") == {:error, :not_found}
    assert File.read(Path.join(root, "vault/draft.md")) == {:error, :enoent}
  end

  test "rebuilds all index records from content storage", %{index: index, storage: storage} do
    assert :ok =
             LocalFs.write_note(
               storage,
               "external",
               "# External edit\n\nWritten outside the index process."
             )

    assert Index.get_note(index, "external") == {:error, :not_found}
    assert :ok = Index.rebuild!(index)
    assert {:ok, note} = Index.get_note(index, "external")
    assert note.title == "External edit"
    assert {:ok, [result]} = Index.search(index, "outside")
    assert result.id == "external"
  end

  test "paginates notes in stable path order", %{index: index} do
    assert {:ok, _note} = Index.write_note(index, "second", "# Second", path: "b/second")
    assert {:ok, _note} = Index.write_note(index, "first", "# First", path: "a/first")

    assert {:ok, page} = Index.list_notes(index, limit: 1, offset: 0)
    assert Enum.map(page.data, & &1.id) == ["first"]
    assert page.pagination == %{limit: 1, offset: 0, total: 2}
  end

  test "returns stable errors for missing, empty, and invalid requests", %{index: index} do
    assert Index.get_note(index, "missing") == {:error, :not_found}
    assert Index.graph(index, "missing") == {:error, :not_found}
    assert Index.delete_note(index, "missing") == {:error, :not_found}
    assert Index.search(index, "") == {:ok, []}
    assert Index.search(index, "?!") == {:ok, []}
    assert Index.search(index, 42) == {:error, :invalid_query}
    assert Index.list_notes(index, "missing-vault", []) == {:error, :not_found}
    assert Index.search(index, "missing-vault", "phrase", []) == {:error, :not_found}
    assert Index.write_note(index, nil, "body") == {:error, :invalid_note}
    assert Index.delete_note(index, nil) == {:error, :invalid_note}
    assert Index.agent_auth(index, :unsupported) == {:error, :unsupported_operation}
  end

  test "restores content storage when an index constraint rejects a write", %{
    index: index,
    root: root
  } do
    assert {:ok, _note} = Index.write_note(index, "first", "# First", path: "shared/path")

    assert {:error, _reason} =
             Index.write_note(index, "second", "# Second", path: "shared/path")

    assert File.read(Path.join(root, "vault/second.md")) == {:error, :enoent}
    assert {:ok, original} = Index.get_note(index, "first")
    assert original.body == "# First"

    assert {:ok, _note} = Index.write_note(index, "second", "# Original second")

    assert {:error, _reason} =
             Index.write_note(index, "second", "# Rejected replacement", path: "shared/path")

    assert File.read(Path.join(root, "vault/second.md")) == {:ok, "# Original second"}
  end

  test "indexes a newly resolved wikilink and ignores unresolved targets", %{index: index} do
    assert {:ok, source} =
             Index.write_note(index, "source", "# Source\n\nSee [[Future note]] and [[Unknown]].")

    assert source.links == []
    assert {:ok, _target} = Index.write_note(index, "future", "# Future note")
    assert {:ok, refreshed} = Index.get_note(index, "source")
    assert Enum.map(refreshed.links, & &1.target_id) == ["future"]
  end

  test "isolates duplicate note identifiers, search, backlinks, and rebuilds by vault", %{
    index: index,
    storage: storage
  } do
    assert {:ok, user} =
             Accounts.create_user(%{"id" => "reader", "email" => "reader@example.com"}, Repo)

    assert {:ok, first_vault} =
             Accounts.create_vault(user.id, %{"id" => "first-vault", "name" => "First"}, Repo)

    assert {:ok, second_vault} =
             Accounts.create_vault(user.id, %{"id" => "second-vault", "name" => "Second"}, Repo)

    assert {:ok, _note} =
             Index.write_note(
               index,
               first_vault.id,
               "shared",
               "# First shared note\n\nA private apricot phrase.",
               []
             )

    assert {:ok, _note} =
             Index.write_note(
               index,
               second_vault.id,
               "shared",
               "# Second shared note\n\nA private blueberry phrase.",
               []
             )

    assert {:ok, _source} =
             Index.write_note(
               index,
               first_vault.id,
               "source",
               "# Source\n\nSee [[First shared note]].",
               []
             )

    assert {:ok, [result]} = Index.search(index, first_vault.id, "apricot", [])
    assert result.title == "First shared note"
    assert {:ok, []} = Index.search(index, second_vault.id, "apricot", [])

    assert {:ok, [backlink]} = Index.backlinks(index, first_vault.id, "shared")
    assert backlink.id == "source"
    assert {:ok, []} = Index.backlinks(index, second_vault.id, "shared")

    assert {:ok, first} = Index.get_note(index, first_vault.id, "shared")
    assert {:ok, second} = Index.get_note(index, second_vault.id, "shared")
    assert first.body =~ "apricot"
    assert second.body =~ "blueberry"

    assert :ok =
             LocalFs.write_note(
               storage,
               "vaults/first-vault/external",
               "# First external note"
             )

    assert :ok = Index.rebuild!(index, first_vault.id)
    assert {:ok, _note} = Index.get_note(index, first_vault.id, "external")
    assert {:ok, second_after_rebuild} = Index.get_note(index, second_vault.id, "shared")
    assert second_after_rebuild.body =~ "blueberry"
  end
end
