defmodule Markdow.OperationsTest do
  use Markdow.DataCase, async: true

  alias Markdow.Accounts
  alias Markdow.Index
  alias Markdow.Operations

  setup :verify_on_exit!

  test "uses the shared operation catalog when delegating service health" do
    expect(Index, :health, fn :isolated_index -> :ok end)

    assert Operations.call("health", %{}, :isolated_index) == {:ok, %{status: "ok"}}
  end

  test "creates, updates, imports, and deletes notes through operation arguments", %{index: index} do
    assert {:ok, user} =
             Operations.call(
               "create_user",
               %{"id" => "writer", "email" => "writer@example.com", "name" => "Writer"},
               index
             )

    assert {:ok, vault} =
             Operations.call(
               "create_vault",
               %{"id" => "work", "user_id" => user.id, "name" => "Work"},
               index
             )

    assert {:ok, created} =
             Operations.call(
               "create_note",
               %{
                 "vault_id" => vault.id,
                 "title" => "A new note",
                 "body" => "# A new note\n\nInitial body",
                 "metadata" => %{"tags" => ["created"]}
               },
               index
             )

    assert created.id == "a-new-note"
    assert created.tags == ["created"]

    assert {:ok, updated} =
             Operations.call(
               "update_note",
               %{
                 "vault_id" => vault.id,
                 "id" => created.id,
                 "body" => "# Updated\n\nReplacement"
               },
               index
             )

    assert updated.title == "Updated"

    assert {:ok, imported} =
             Operations.call(
               "import_note",
               %{
                 "vault_id" => vault.id,
                 "filename" => "Meeting Notes.md",
                 "body" => "# Meeting notes"
               },
               index
             )

    assert imported.id == "Meeting Notes"
    assert imported.path == "Meeting Notes"

    assert Operations.call(
             "delete_note",
             %{"vault_id" => vault.id, "id" => created.id},
             index
           ) == {:ok, %{vault_id: vault.id, id: created.id, deleted: true}}

    assert {:ok, [listed_vault]} = Operations.call("list_vaults", %{"user_id" => user.id}, index)
    assert listed_vault.id == vault.id
  end

  test "reports invalid arguments and unknown operations", %{index: index} do
    assert Operations.call("get_note", %{}, index) == {:error, :invalid_arguments}
    assert Operations.call("does_not_exist", %{}, index) == {:error, :unknown_operation}
  end

  test "does not create users through the shared operation catalog while registrations are closed",
       %{
         index: index
       } do
    closed_index = %{index | signups_enabled: false}

    assert Operations.call(
             "create_user",
             %{"email" => "new@example.com"},
             closed_index
           ) == {:error, :signups_disabled}
  end

  test "round-trips path-preserving Markdown and binary documents", %{index: index} do
    markdown = "# Same name\n\nThe folder remains part of the identity."
    image = <<0, 255, 12, 10, 200>>

    assert {:ok, note_document} =
             Operations.call(
               "write_document",
               %{
                 "vault_id" => "default",
                 "path" => "Wiki/Same name.md",
                 "data_base64" => Base.encode64(markdown)
               },
               index
             )

    assert note_document.path == "Wiki/Same name.md"
    assert note_document.kind == "note"

    assert {:ok, read_markdown} =
             Operations.call(
               "read_document",
               %{"vault_id" => "default", "path" => "Wiki/Same name.md"},
               index
             )

    assert Base.decode64!(read_markdown.data_base64) == markdown

    assert {:ok, _second_note} =
             Operations.call(
               "write_document",
               %{
                 "vault_id" => "default",
                 "path" => "Reading/Same name.md",
                 "data_base64" => Base.encode64("# Another")
               },
               index
             )

    assert {:ok, %{path: "Árbol/mañana's note.md"}} =
             Operations.call(
               "write_document",
               %{
                 "vault_id" => "default",
                 "path" => "Árbol/mañana's note.md",
                 "data_base64" => Base.encode64("# Mañana")
               },
               index
             )

    assert {:ok, %{path: ".obsidian/plugins/example/data.json", kind: "asset"}} =
             Operations.call(
               "write_document",
               %{
                 "vault_id" => "default",
                 "path" => ".obsidian/plugins/example/data.json",
                 "data_base64" => Base.encode64(~s({"enabled":true}))
               },
               index
             )

    assert {:ok, asset_document} =
             Operations.call(
               "write_document",
               %{
                 "vault_id" => "default",
                 "path" => "Assets/Pasted image 2026.png",
                 "data_base64" => Base.encode64(image)
               },
               index
             )

    assert asset_document.media_type == "image/png"
    assert asset_document.size == byte_size(image)

    assert {:ok, listed} = Operations.call("list_documents", %{"vault_id" => "default"}, index)
    assert Enum.any?(listed, &(&1.path == "Wiki/Same name.md" and &1.kind == "note"))

    assert Enum.any?(
             listed,
             &(&1.path == "Assets/Pasted image 2026.png" and &1.kind == "asset")
           )

    assert {:ok, read_image} =
             Operations.call(
               "read_document",
               %{"vault_id" => "default", "path" => "Assets/Pasted image 2026.png"},
               index
             )

    assert Base.decode64!(read_image.data_base64) == image

    assert Operations.call(
             "delete_document",
             %{"vault_id" => "default", "path" => "Assets/Pasted image 2026.png"},
             index
           ) ==
             {:ok, %{vault_id: "default", path: "Assets/Pasted image 2026.png", deleted: true}}

    assert Operations.call(
             "read_document",
             %{"vault_id" => "default", "path" => "Assets/Pasted image 2026.png"},
             index
           ) == {:error, :not_found}
  end

  test "normalizes a Markdown filename accepted by note creation", %{index: index} do
    assert {:ok, note} =
             Operations.call(
               "create_note",
               %{
                 "vault_id" => "default",
                 "path" => "Projects/Agent check.md",
                 "body" => "# Agent check\n"
               },
               index
             )

    assert note.id == "agent-check"
    assert note.path == "Projects/Agent check"

    assert {:ok, document} =
             Operations.call(
               "read_document",
               %{"vault_id" => "default", "path" => "Projects/Agent check.md"},
               index
             )

    assert Base.decode64!(document.data_base64) == "# Agent check\n"

    assert {:ok, documents} =
             Operations.call("list_documents", %{"vault_id" => "default"}, index)

    assert Enum.count(documents, &(&1.path == "Projects/Agent check.md")) == 1
  end

  test "rejects unsafe, malformed, and oversized documents", %{index: index} do
    assert Operations.call(
             "write_document",
             %{"vault_id" => "default", "path" => "../secret", "data_base64" => "eA=="},
             index
           ) == {:error, :invalid_path}

    assert Operations.call(
             "write_document",
             %{"vault_id" => "default", "path" => "file.bin", "data_base64" => "***"},
             index
           ) == {:error, :invalid_base64}

    assert Operations.call(
             "write_document",
             %{
               "vault_id" => "default",
               "path" => "invalid.md",
               "data_base64" => Base.encode64(<<255>>)
             },
             index
           ) == {:error, :invalid_utf8}

    oversized = :binary.copy(<<0>>, 5 * 1_024 * 1_024 + 1)

    assert Operations.call(
             "write_document",
             %{
               "vault_id" => "default",
               "path" => "large.bin",
               "data_base64" => Base.encode64(oversized)
             },
             index
           ) == {:error, :document_too_large}
  end

  test "enforces the authenticated user at the shared operation boundary", %{index: index} do
    assert {:ok, first_user} =
             Operations.call(
               "create_user",
               %{"id" => "first", "email" => "first@example.com"},
               index
             )

    assert {:ok, second_user} =
             Operations.call(
               "create_user",
               %{"id" => "second", "email" => "second@example.com"},
               index
             )

    assert {:ok, first_vault} =
             Operations.call(
               "create_vault",
               %{"id" => "first-vault", "user_id" => first_user.id, "name" => "First"},
               index
             )

    assert {:ok, second_vault} =
             Operations.call(
               "create_vault",
               %{"id" => "second-vault", "user_id" => second_user.id, "name" => "Second"},
               index
             )

    authorization = %{kind: :access_token, user_id: first_user.id}

    assert {:ok, [visible_user]} =
             Operations.call("list_users", %{}, index, authorization)

    assert visible_user.id == first_user.id

    assert Operations.call(
             "get_user",
             %{"id" => second_user.id},
             index,
             authorization
           ) == {:error, :forbidden}

    assert Operations.call(
             "list_vaults",
             %{"user_id" => second_user.id},
             index,
             authorization
           ) == {:error, :forbidden}

    assert Operations.call(
             "get_vault",
             %{"id" => second_vault.id},
             index,
             authorization
           ) == {:error, :forbidden}

    assert Operations.call(
             "create_vault",
             %{"user_id" => second_user.id, "name" => "Stolen"},
             index,
             authorization
           ) == {:error, :forbidden}

    assert Operations.call(
             "create_note",
             %{"vault_id" => second_vault.id, "body" => "# Stolen"},
             index,
             authorization
           ) == {:error, :forbidden}

    assert {:ok, note} =
             Operations.call(
               "create_note",
               %{"vault_id" => first_vault.id, "body" => "# Allowed"},
               index,
               authorization
             )

    assert note.vault_id == first_vault.id

    assert Operations.call(
             "create_user",
             %{"email" => "third@example.com"},
             index,
             authorization
           ) == {:error, :forbidden}

    assert Operations.call(
             "revoke_agent_credentials",
             %{"user_id" => second_user.id},
             index,
             authorization
           ) == {:error, :forbidden}
  end

  @vault_operations ~w(
    list_notes get_note create_note update_note delete_note search_notes
    list_backlinks get_note_graph import_note rebuild_index list_documents
    read_document write_document delete_document embed_text
  )

  @account_operations ~w(
    list_vaults create_vault get_embedding_configuration configure_embedding
    validate_embedding_configuration delete_embedding_configuration
  )

  @unscoped_operations ~w(
    health list_users create_user revoke_agent_credentials get_user get_vault
  )

  test "every operation authorizes the resource it acts on, whatever else the arguments carry",
       %{index: index} do
    {:ok, attacker} = Accounts.create_user(%{"email" => "attacker@example.com"}, index.repo)
    {:ok, victim} = Accounts.create_user(%{"email" => "victim@example.com"}, index.repo)

    {:ok, attacker_vault} =
      Accounts.create_vault(attacker.id, %{"name" => "Attacker"}, index.repo)

    {:ok, victim_vault} = Accounts.create_vault(victim.id, %{"name" => "Victim"}, index.repo)
    authorization = %{kind: :access_token, user_id: attacker.id}

    # Authorization used to be chosen by the shape of the arguments, so a caller
    # could pick which check ran by adding a key. Each call below carries every
    # identifier at once, naming a resource it owns alongside one it does not.
    assert Operations.call(
             "get_user",
             %{"id" => victim.id, "user_id" => attacker.id, "vault_id" => attacker_vault.id},
             index,
             authorization
           ) == {:error, :forbidden}

    assert Operations.call(
             "get_vault",
             %{
               "id" => victim_vault.id,
               "user_id" => attacker.id,
               "vault_id" => attacker_vault.id
             },
             index,
             authorization
           ) == {:error, :forbidden}

    for name <- @account_operations do
      assert Operations.call(
               name,
               %{"user_id" => victim.id, "vault_id" => attacker_vault.id, "id" => attacker.id},
               index,
               authorization
             ) == {:error, :forbidden},
             name
    end

    for name <- @vault_operations do
      assert Operations.call(
               name,
               %{
                 "vault_id" => victim_vault.id,
                 "user_id" => attacker.id,
                 "id" => attacker_vault.id
               },
               index,
               authorization
             ) == {:error, :forbidden},
             name
    end

    # Fails when an operation is added without being placed in one of the
    # groups above, so a new operation cannot quietly skip this test.
    assert MapSet.new(@unscoped_operations ++ @account_operations ++ @vault_operations) ==
             MapSet.new(Operations.names())
  end
end
