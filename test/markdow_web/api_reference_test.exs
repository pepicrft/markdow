defmodule MarkdowWeb.ApiReferenceTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  test "renders Scalar against the OpenApiSpex document without persisting credentials" do
    response =
      :get
      |> Plug.Test.conn("/docs")
      |> put_req_header("accept", "text/html")
      |> MarkdowWeb.Endpoint.call([])

    assert response.status == 200
    assert response.resp_body =~ "@scalar/api-reference@1.64.1"
    assert response.resp_body =~ "url: '/openapi.json'"
    assert response.resp_body =~ "persistAuth: false"
    assert response.resp_body =~ "telemetry: false"
    assert response.resp_body =~ "agent: { disabled: true }"
    assert response.resp_body =~ "sha384-SmFRDuBBmEoCbbBCTcn8"

    [policy] = get_resp_header(response, "content-security-policy")
    assert policy =~ "https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.64.1"
    assert policy =~ "connect-src 'self'"
  end
end
