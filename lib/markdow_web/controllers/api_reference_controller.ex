defmodule MarkdowWeb.ApiReferenceController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema

  @scalar_url "https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.64.1"
  @scalar_integrity "sha384-SmFRDuBBmEoCbbBCTcn8/+cIQONyH0xgOKpsp6OttBlI8uG9uc6iAO8SonYQ3e1W"

  tags ["Documentation"]
  security []

  operation :show,
    operation_id: "api_reference",
    summary: "Browse the interactive application programming interface reference",
    responses: [ok: {"Interactive reference", "text/html", %Schema{type: :string}}]

  def show(conn, _params) do
    nonce = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)

    body = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="description" content="Interactive reference for the Markdow application programming interface.">
        <title>Markdow application programming interface reference</title>
      </head>
      <body>
        <noscript><p>JavaScript is required for the interactive reference. The <a href="/openapi.json">OpenAPI document</a> remains available directly.</p></noscript>
        <div id="app"></div>
        <script src="#{@scalar_url}" integrity="#{@scalar_integrity}" crossorigin="anonymous"></script>
        <script nonce="#{nonce}">
          Scalar.createApiReference('#app', {
            url: '/openapi.json',
            theme: 'none',
            persistAuth: false,
            telemetry: false,
            withDefaultFonts: false,
            showOperationId: true,
            agent: { disabled: true }
          })
        </script>
      </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html", "utf-8")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header(
      "content-security-policy",
      "default-src 'none'; script-src '#{nonce_source(nonce)}' #{@scalar_url}; connect-src 'self'; style-src 'unsafe-inline'; img-src 'self' data: https:; font-src data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
    )
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, body)
  end

  defp nonce_source(nonce), do: "nonce-#{nonce}"
end
