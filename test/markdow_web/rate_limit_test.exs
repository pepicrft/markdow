defmodule MarkdowWeb.RateLimitTest do
  use Markdow.DataCase, async: true

  import Plug.Conn

  alias Markdow.DataCase
  alias Markdow.RateLimit

  setup :verify_on_exit!

  test "allows a request and publishes the remaining Hammer budget", %{index: index} do
    expect(RateLimit, :hit, fn key, 60_000, 120 ->
      assert key =~ "api:address:"
      {:allow, 7}
    end)

    response = DataCase.endpoint_conn(:get, "/health", nil, index, nil, "test", rate_limits())

    assert response.status == 200
    assert get_resp_header(response, "x-ratelimit-limit") == ["120"]
    assert get_resp_header(response, "x-ratelimit-remaining") == ["113"]
  end

  test "returns a retry time when Hammer denies a request", %{index: index} do
    expect(RateLimit, :hit, fn _key, 60_000, 120 -> {:deny, 1_500} end)

    response = DataCase.endpoint_conn(:get, "/health", nil, index, nil, "test", rate_limits())

    assert response.status == 429
    assert get_resp_header(response, "retry-after") == ["2"]
    assert JSON.decode!(response.resp_body) == %{"error" => "rate_limit_exceeded"}
  end

  test "throttles the public agent registration instructions", %{index: index} do
    expect(RateLimit, :hit, fn key, 60_000, 60 ->
      assert key =~ "documentation:address:"
      {:deny, 1_000}
    end)

    response = DataCase.endpoint_conn(:get, "/auth.md", nil, index, nil, "test", rate_limits())

    assert response.status == 429
    assert response.resp_body == "Too many requests"
  end

  defp rate_limits do
    [
      marketing: [scale_ms: 60_000, limit: 60],
      documentation: [scale_ms: 60_000, limit: 60],
      api: [scale_ms: 60_000, limit: 120],
      authentication: [scale_ms: 60_000, limit: 30],
      model_context_protocol: [scale_ms: 60_000, limit: 120]
    ]
  end
end
