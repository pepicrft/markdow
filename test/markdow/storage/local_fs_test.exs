defmodule Markdow.Storage.LocalFsTest do
  use ExUnit.Case, async: true

  alias Markdow.Storage
  alias Markdow.Storage.LocalFs

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "markdow-storage-#{System.unique_integer([:positive, :monotonic])}"
      )

    spec =
      Supervisor.child_spec(
        {LocalFs, path: root, name: nil},
        id: {:storage, System.unique_integer([:positive])}
      )

    {:ok, storage} = start_supervised(spec)
    on_exit(fn -> File.rm_rf(root) end)

    {:ok, root: root, storage: storage}
  end

  test "writes, lists, reads, and deletes nested notes", %{root: root, storage: storage} do
    assert :ok = LocalFs.write_note(storage, "projects/markdow", "# Markdow")
    assert File.read(Path.join(root, "projects/markdow.md")) == {:ok, "# Markdow"}
    assert LocalFs.list_notes(storage) == {:ok, ["projects/markdow"]}
    assert LocalFs.read_note(storage, "projects/markdow") == {:ok, "# Markdow"}
    assert :ok = LocalFs.delete_note(storage, "projects/markdow")
    assert LocalFs.read_note(storage, "projects/markdow") == {:error, :enoent}
  end

  test "stores binary assets below the reserved assets directory", %{root: root, storage: storage} do
    storage_reference = {LocalFs, storage}

    assert :ok = Storage.write_asset(storage_reference, "images/diagram.bin", <<0, 1, 2>>)
    assert :ok = Storage.write_asset(storage_reference, "documents/reference.md", "# Not a note")
    assert Storage.read_asset(storage_reference, "images/diagram.bin") == {:ok, <<0, 1, 2>>}
    assert File.read(Path.join(root, "assets/images/diagram.bin")) == {:ok, <<0, 1, 2>>}

    assert Storage.list_assets(storage_reference) ==
             {:ok, ["documents/reference.md", "images/diagram.bin"]}

    assert Storage.list_notes(storage_reference) == {:ok, []}
    assert :ok = Storage.delete_asset(storage_reference, "images/diagram.bin")
    assert Storage.read_asset(storage_reference, "images/diagram.bin") == {:error, :enoent}
  end

  test "dispatches note operations through the storage contract", %{storage: storage} do
    storage_reference = {LocalFs, storage}

    assert :ok = Storage.write_note(storage_reference, "contract", "# Contract")
    assert Storage.read_note(storage_reference, "contract") == {:ok, "# Contract"}
    assert :ok = Storage.delete_note(storage_reference, "contract")
    assert Storage.read_note(storage_reference, "contract") == {:error, :enoent}
  end

  test "rejects traversal and absolute paths", %{storage: storage} do
    assert LocalFs.write_note(storage, "../outside", "no") == {:error, :invalid_path}
    assert LocalFs.read_note(storage, "/tmp/outside") == {:error, :invalid_path}
    assert LocalFs.write_note(storage, "assets/hidden", "no") == {:error, :invalid_path}
    assert LocalFs.read_note(storage, "assets/hidden") == {:error, :invalid_path}

    assert LocalFs.write_asset(storage, "images/../../outside", "no") ==
             {:error, :invalid_path}

    assert LocalFs.read_asset(storage, 42) == {:error, :invalid_path}
  end

  test "does not follow symbolic links outside the configured root", %{
    storage: storage,
    root: root
  } do
    outside =
      Path.join(System.tmp_dir!(), "markdow-outside-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(outside) end)

    File.mkdir_p!(outside)
    File.write!(Path.join(outside, "secret.md"), "outside")
    File.ln_s!(outside, Path.join(root, "linked"))
    File.mkdir_p!(Path.join(root, "assets"))
    File.ln_s!(outside, Path.join([root, "assets", "linked"]))

    assert {:error, :invalid_path} = LocalFs.read_note(storage, "linked/secret")
    assert {:error, :invalid_path} = LocalFs.write_note(storage, "linked/new", "blocked")
    assert {:error, :invalid_path} = LocalFs.read_asset(storage, "linked/secret.md")
    assert {:error, :invalid_path} = LocalFs.write_asset(storage, "linked/new", "blocked")
    assert {:ok, []} = LocalFs.list_notes(storage)
    assert {:ok, []} = LocalFs.list_assets(storage)
  end
end
