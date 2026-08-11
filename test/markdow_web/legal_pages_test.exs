defmodule MarkdowWeb.LegalPagesTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  test "publishes concise terms, privacy, and cookie pages" do
    terms = request("/terms")
    privacy = request("/privacy")
    cookies = request("/cookies")

    assert terms.status == 200
    assert terms.resp_body =~ "There is no charge for the hosted service at present."
    assert terms.resp_body =~ "Provider information"
    assert terms.resp_body =~ "Mandatory consumer rights remain unaffected."

    assert privacy.status == 200
    assert privacy.resp_body =~ "Account data"
    assert privacy.resp_body =~ "in-memory abuse-prevention counters"
    assert privacy.resp_body =~ "anonymous page and named interaction events"
    assert privacy.resp_body =~ "jsDelivr"

    assert cookies.status == 200
    assert cookies.resp_body =~ "do not set analytics cookies"
    assert cookies.resp_body =~ "authentication persistence and telemetry disabled"

    Enum.each([terms, privacy, cookies], fn response ->
      assert get_resp_header(response, "cache-control") == ["no-store"]
      assert get_resp_header(response, "content-type") == ["text/html; charset=utf-8"]
    end)
  end

  test "disables every marketing route without disabling operational documentation" do
    for path <- ["/", "/terms", "/privacy", "/cookies"] do
      assert request(path, false).status == 404
    end

    assert request("/docs", false).status == 200
  end

  defp request(path, marketing_routes \\ true) do
    :get
    |> Plug.Test.conn(path)
    |> put_private(:markdow_marketing_routes, marketing_routes)
    |> put_req_header("accept", "text/html")
    |> MarkdowWeb.Endpoint.call([])
  end
end
