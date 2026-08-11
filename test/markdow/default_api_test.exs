defmodule Markdow.DefaultApiTest do
  use Markdow.DataCase, async: true

  alias Markdow.AgentAuth
  alias Markdow.Index
  alias Markdow.Storage.LocalFs

  test "keeps the read-only default process interfaces available" do
    missing = "missing-#{System.unique_integer([:positive])}"

    assert Index.health() == :ok
    assert {:ok, %{data: _notes}} = Index.list_notes()
    assert Index.search(missing) == {:ok, []}
    assert Index.get_note(missing) == {:error, :not_found}
    assert Index.backlinks(missing) == {:error, :not_found}
    assert Index.graph(missing) == {:error, :not_found}
    assert {:ok, _count} = Index.agent_auth({:registration_count_since, 0})

    assert {:ok, _notes} = LocalFs.list_notes()
    assert LocalFs.read_note(missing) == {:error, :enoent}
    assert LocalFs.read_asset(missing) == {:error, :enoent}
  end

  test "keeps malformed default authentication calls safe" do
    assert AgentAuth.create_service_registration(nil) == {:error, :invalid_request}
    assert AgentAuth.get_claim_attempt(nil) == {:error, :invalid_claim_token}
    assert AgentAuth.confirm_claim(nil, nil, nil) == {:error, :invalid_request}
    assert AgentAuth.exchange_claim(nil) == {:error, :invalid_request}
    assert AgentAuth.exchange_assertion(nil) == {:error, :invalid_request}
    assert AgentAuth.authorize(nil, []) == {:error, :invalid_token}
    assert AgentAuth.revoke_access_token(nil) == {:error, :invalid_token}
    assert {:ok, %{keys: [_key]}} = AgentAuth.jwks()
  end
end
