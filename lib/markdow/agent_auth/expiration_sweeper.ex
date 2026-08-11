defmodule Markdow.AgentAuth.ExpirationSweeper do
  @moduledoc "Expires abandoned auth.md registrations and records their audit events."

  use GenServer

  require Logger

  alias Markdow.Index

  @interval :timer.minutes(1)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec sweep(Index.Context.t(), integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def sweep(index \\ Index.context(), current_time \\ System.system_time(:second)) do
    Index.agent_auth(index, {:expire_due_registrations, current_time})
  end

  @impl true
  def init(opts) do
    state = %{
      index: Keyword.get_lazy(opts, :index, &Index.context/0),
      interval: Keyword.get(opts, :interval, @interval)
    }

    send(self(), :sweep)
    {:ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    case sweep(state.index) do
      {:ok, _count} ->
        :ok

      {:error, reason} ->
        Logger.warning("Agent registration expiration failed: #{inspect(reason)}")
    end

    Process.send_after(self(), :sweep, state.interval)
    {:noreply, state}
  end
end
