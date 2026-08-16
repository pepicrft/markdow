defmodule MarkdowWeb.Telemetry do
  @moduledoc """
  Periodic virtual machine measurements and the OpenTelemetry metric exporter.

  Metrics are described once here with `Telemetry.Metrics` and pushed over OTLP
  to the collector configured by `OTEL_EXPORTER_OTLP_ENDPOINT`. When no endpoint
  is configured the exporter is not started at all, so a development machine or
  a self-hosted instance without a collector runs the poller and nothing else.
  """

  use Supervisor

  import Telemetry.Metrics

  @export_period :timer.seconds(15)
  @poll_period :timer.seconds(10)

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl Supervisor
  def init(_arg) do
    children =
      [{:telemetry_poller, measurements: periodic_measurements(), period: @poll_period}] ++
        exporter_children()

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  The metric definitions exported over OTLP.

  Request metrics are tagged with the method and status rather than the full
  path so the cardinality stays bounded, and the route tag comes from the
  router's pattern for the same reason.
  """
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      counter("phoenix.endpoint.stop.count",
        event_name: [:phoenix, :endpoint, :stop],
        tags: [:method, :status],
        tag_values: &endpoint_tag_values/1,
        description: "Number of completed web requests"
      ),
      distribution("phoenix.endpoint.stop.duration",
        tags: [:method, :status],
        tag_values: &endpoint_tag_values/1,
        unit: {:native, :millisecond}
      ),
      distribution("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      counter("phoenix.router_dispatch.exception.count",
        event_name: [:phoenix, :router_dispatch, :exception],
        tags: [:kind, :route],
        description: "Number of requests that raised out of the router"
      ),
      distribution("phoenix.router_dispatch.exception.duration",
        tags: [:kind, :route],
        unit: {:native, :millisecond}
      ),
      distribution("markdow.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other query measurements"
      ),
      distribution("markdow.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding data received from the database"
      ),
      distribution("markdow.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      distribution("markdow.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      distribution("markdow.repo.query.idle_time",
        unit: {:native, :millisecond},
        description: "The time the connection waited before it was checked out"
      ),
      last_value("vm.memory.total", unit: {:byte, :kilobyte}),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io")
    ]
  end

  defp exporter_children do
    if Application.get_env(:markdow, :observability_enabled, false) do
      [{OtelMetricExporter, metrics: metrics(), export_period: @export_period}]
    else
      []
    end
  end

  defp endpoint_tag_values(%{conn: conn}), do: %{method: conn.method, status: conn.status}

  defp periodic_measurements, do: []
end
