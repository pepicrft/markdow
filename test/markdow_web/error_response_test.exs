defmodule MarkdowWeb.ErrorResponseTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  test "renders an unknown browser route as a headless error without crashing" do
    response = request("text/html")

    assert response.status == 404
    assert get_resp_header(response, "content-type") == ["application/json; charset=utf-8"]
    assert JSON.decode!(response.resp_body) == %{"error" => "not_found"}
  end

  test "renders an unknown headless route with the stable error shape" do
    response = request("application/json")

    assert response.status == 404
    assert get_resp_header(response, "content-type") == ["application/json; charset=utf-8"]
    assert JSON.decode!(response.resp_body) == %{"error" => "not_found"}
  end

  test "renders internal JSON errors with the existing operation error" do
    assert MarkdowWeb.ErrorJSON.render("500.json", %{}) == %{error: "operation_failed"}
  end

  test "maps document, provider, and unexpected operation failures" do
    assert api_error(:document_too_large) == {413, %{"error" => "document_too_large"}}

    assert api_error(:embedding_provider_unavailable) ==
             {503, %{"error" => "embedding_provider_unavailable"}}

    assert api_error(:unexpected_failure) == {500, %{"error" => "operation_failed"}}
  end

  defp request(accept) do
    :get
    |> Plug.Test.conn("/not-a-markdow-route")
    |> put_req_header("accept", accept)
    |> MarkdowWeb.Endpoint.call([])
  end

  defp api_error(reason) do
    response =
      :get
      |> Plug.Test.conn("/")
      |> MarkdowWeb.ApiResponse.send_result({:error, reason})

    {response.status, JSON.decode!(response.resp_body)}
  end
end
