defmodule MarkdowWeb.HomePageTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  test "introduces the headless note system at the root path" do
    response = request()

    assert response.status == 200
    assert get_resp_header(response, "content-type") == ["text/html; charset=utf-8"]
    assert get_resp_header(response, "cache-control") == ["no-store"]

    assert response.resp_body =~
             "<title>Markdow — Programmatic access to Markdown notes</title>"

    assert response.resp_body =~
             "A semantic layer for your Markdown."

    assert response.resp_body =~ "The files remain ordinary Markdown."
    assert response.resp_body =~ "There is no second copy of your notes to keep in sync."
    refute response.resp_body =~ "What it is not"
    assert response.resp_body =~ "The file is the durable part."
    assert response.resp_body =~ "There is very little machinery."
    assert response.resp_body =~ "Work with notes from any client."
    assert response.resp_body =~ "Copy this into your agent."
    assert response.resp_body =~ "Sign me up for Markdow using https://markdow.org/auth.md."
    assert response.resp_body =~ ~s(data-copy-target="agent-signup-prompt")
    assert response.resp_body =~ ~s(aria-label="Copy the agent sign-up prompt")
    assert response.resp_body =~ "Markdow is small enough to change."
    assert response.resp_body =~ ~s(href="https://github.com/pepicrft/markdow/issues")
    assert response.resp_body =~ "Prefer to host Markdow yourself? Go for it."
    refute response.resp_body =~ "The first version"

    assert response.resp_body =~
             ~s(href="/openapi.json" title="Representational State Transfer application programming interface">REST API</a>)

    assert response.resp_body =~
             ~s(href="/.well-known/mcp/server-card.json" title="Model Context Protocol">MCP server</a>)
  end

  test "links people to the operational interfaces" do
    body = request().resp_body

    assert body =~ ~s(href="/health")
    assert body =~ ~s(href="/docs")
    assert body =~ ~s(href="/openapi.json")
    assert body =~ ~s(href="/auth.md")
    assert body =~ ~s(href="/terms")
    assert body =~ ~s(href="/privacy")
    assert body =~ ~s(href="/cookies")
    assert body =~ ~s(href="https://github.com/pepicrft/markdow")

    assert body =~
             ~s(href="https://modelcontextprotocol.io/" title="Model Context Protocol">MCP</a>)
  end

  test "loads only the local interaction script unless analytics is enabled" do
    response = request()

    assert get_resp_header(response, "content-security-policy") == [
             "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
           ]

    assert response.resp_body =~ ~s(<script defer src="/assets/home.js"></script>)
    refute response.resp_body =~ "<script>"
    refute response.resp_body =~ "<link"
    assert response.resp_body =~ "prefers-reduced-motion"

    script =
      :get
      |> Plug.Test.conn("/assets/home.js")
      |> MarkdowWeb.Endpoint.call([])

    assert script.status == 200
    assert script.resp_body =~ "navigator.clipboard?.writeText"
    assert script.resp_body =~ "document.execCommand"
    assert script.resp_body =~ ~s(button.textContent = "Copied")
  end

  test "loads anonymous analytics only when explicitly configured" do
    response =
      :get
      |> Plug.Test.conn("/")
      |> put_req_header("accept", "text/html")
      |> put_private(:markdow_analytics,
        enabled: true,
        host: "https://analytics.example.com",
        write_key: "public-write-key"
      )
      |> MarkdowWeb.Endpoint.call([])

    assert response.resp_body =~ ~s(name="smolanalytics-host")
    assert response.resp_body =~ ~s(src="/assets/analytics.js")
    assert response.resp_body =~ ~s(data-analytics-event="documentation_opened")

    assert get_resp_header(response, "content-security-policy") == [
             "default-src 'none'; script-src 'self' https://analytics.example.com; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
           ]
  end

  defp request do
    :get
    |> Plug.Test.conn("/")
    |> put_req_header("accept", "text/html")
    |> MarkdowWeb.Endpoint.call([])
  end
end
