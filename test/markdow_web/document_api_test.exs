defmodule MarkdowWeb.DocumentApiTest do
  use Markdow.DataCase, async: true

  alias Markdow.DataCase

  test "creates, lists, reads, and deletes nested documents through the web interface", %{
    index: index
  } do
    path = "Assets/Pasted image 2026.png"
    encoded_path = encode_path(path)
    bytes = <<137, 80, 78, 71, 0, 255>>

    stored =
      index
      |> request(:put, "/vaults/default/documents/#{encoded_path}", %{
        "data_base64" => Base.encode64(bytes)
      })
      |> json_response(200)

    assert stored["path"] == path
    assert stored["kind"] == "asset"
    assert stored["media_type"] == "image/png"

    listed =
      index
      |> request(:get, "/vaults/default/documents", nil)
      |> json_response(200)

    assert Enum.any?(listed, &(&1["path"] == path))

    read =
      index
      |> request(:get, "/vaults/default/documents/#{encoded_path}", nil)
      |> json_response(200)

    assert Base.decode64!(read["data_base64"]) == bytes

    deleted =
      index
      |> request(:delete, "/vaults/default/documents/#{encoded_path}", nil)
      |> json_response(200)

    assert deleted == %{"vault_id" => "default", "path" => path, "deleted" => true}
  end

  test "indexes Markdown uploaded at its original relative path", %{index: index} do
    path = "Wiki/Cloud Primitives Are the Wrong Shape.md"

    response =
      index
      |> request(:put, "/vaults/default/documents/#{encode_path(path)}", %{
        "data_base64" => Base.encode64("# Cloud primitives\n\nReview [[Architecture]].")
      })
      |> json_response(200)

    assert response["path"] == path
    assert response["kind"] == "note"

    results =
      index
      |> request(:get, "/vaults/default/search?q=primitives", nil)
      |> json_response(200)

    assert [%{"path" => "Wiki/Cloud Primitives Are the Wrong Shape"}] = results
  end

  defp request(index, method, path, body),
    do: DataCase.endpoint_conn(method, path, body, index, "test")

  defp json_response(conn, status) do
    assert conn.status == status, conn.resp_body
    JSON.decode!(conn.resp_body)
  end

  defp encode_path(path) do
    path
    |> String.split("/")
    |> Enum.map_join("/", &URI.encode(&1, fn character -> URI.char_unreserved?(character) end))
  end
end
