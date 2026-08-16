defmodule Markdow.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    setup_observability()

    storage_config = Application.fetch_env!(:markdow, :storage)

    children =
      [
        MarkdowWeb.Telemetry,
        Markdow.Repo,
        storage_child(storage_config)
      ] ++
        agent_auth_sweeper_child() ++
        [
          Markdow.RateLimit,
          {Finch, name: Markdow.Finch},
          MarkdowWeb.Endpoint
        ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Markdow.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MarkdowWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Traces, structured logs, and the Ecto and web instrumentation are only
  # attached when a collector is configured, so an instance without one does not
  # pay for spans nobody exports. See `config/runtime.exs`.
  defp setup_observability do
    if Application.get_env(:markdow, :observability_enabled, false) do
      :ok = Logger.add_handlers(:markdow)
      :ok = OpentelemetryBandit.setup(public_endpoint: true)
      :ok = OpentelemetryPhoenix.setup(adapter: :bandit)
      :ok = OpentelemetryEcto.setup([:markdow, :repo])
    end

    :ok
  end

  defp storage_child(storage_config) do
    case Keyword.fetch!(storage_config, :driver) do
      "local" ->
        {Markdow.Storage.LocalFs, path: storage_config |> Keyword.fetch!(:path) |> Path.expand()}
    end
  end

  defp agent_auth_sweeper_child do
    if Application.get_env(:markdow, :agent_auth_sweeper, true),
      do: [Markdow.AgentAuth.ExpirationSweeper],
      else: []
  end
end
