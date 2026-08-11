defmodule Markdow.AgentAuth.ExpirationSweeperTest do
  use Markdow.DataCase, async: true

  import ExUnit.CaptureLog

  alias Markdow.AgentAuth.ExpirationSweeper
  alias Markdow.Index

  setup :verify_on_exit!

  test "schedules and completes a sweep", %{index: index} do
    expect(Index, :agent_auth, fn ^index, {:expire_due_registrations, current_time}
                                  when is_integer(current_time) ->
      {:ok, 0}
    end)

    assert {:ok, state} = ExpirationSweeper.init(index: index, interval: 60_000)
    assert_receive :sweep
    assert {:noreply, ^state} = ExpirationSweeper.handle_info(:sweep, state)
  end

  test "logs a failed sweep without stopping the worker", %{index: index} do
    expect(Index, :agent_auth, fn ^index, {:expire_due_registrations, _current_time} ->
      {:error, :database_unavailable}
    end)

    state = %{index: index, interval: 60_000}

    log =
      capture_log(fn ->
        assert {:noreply, ^state} = ExpirationSweeper.handle_info(:sweep, state)
      end)

    assert log =~ "Agent registration expiration failed"
    assert log =~ "database_unavailable"
  end
end
