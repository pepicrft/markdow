defmodule MarkdowWeb.OpenApiTest do
  use Markdow.DataCase, async: true

  alias Markdow.DataCase
  alias Markdow.Operations

  test "documents every shared operation with the same identifier", %{index: index} do
    response = DataCase.endpoint_conn(:get, "/openapi.json", nil, index)
    assert response.status == 200

    document = JSON.decode!(response.resp_body)

    operation_ids =
      document["paths"]
      |> Enum.flat_map(fn {_path, path_item} ->
        path_item
        |> Map.values()
        |> Enum.filter(&is_map/1)
        |> Enum.map(& &1["operationId"])
        |> Enum.reject(&is_nil/1)
      end)
      |> Enum.sort()

    public_operations = [
      "home",
      "api_reference",
      "get_openapi_document",
      "terms_of_service",
      "privacy_policy",
      "cookie_terms",
      "open_graph_image",
      "agent_auth_instructions",
      "register_agent_identity",
      "start_agent_claim",
      "exchange_agent_credential",
      "revoke_agent_credential",
      "register_oauth_client",
      "list_oauth_clients",
      "delete_oauth_client",
      "get_oauth_protected_resource",
      "get_mcp_protected_resource",
      "get_oauth_authorization_server",
      "get_agent_auth_signing_keys",
      "get_mcp_server_card",
      "receive_agent_security_event",
      "show_agent_claim",
      "sign_up_agent_claim_user",
      "sign_in_agent_claim_user",
      "show_agent_claim_email_verification",
      "verify_agent_claim_email",
      "resend_agent_claim_email_verification",
      "confirm_agent_claim",
      "sign_out_agent_claim_user"
    ]

    assert operation_ids == Enum.sort(public_operations ++ Operations.names())
    assert document["components"]["securitySchemes"]["bearerAuth"]["scheme"] == "bearer"
  end

  test "documents the editorial home page as a public HTML operation", %{index: index} do
    document =
      :get
      |> DataCase.endpoint_conn("/openapi.json", nil, index)
      |> Map.fetch!(:resp_body)
      |> JSON.decode!()

    home = document["paths"]["/"]["get"]

    assert home["operationId"] == "home"
    assert home["security"] == []

    assert get_in(home, ["responses", "200", "content", "text/html", "schema", "type"]) ==
             "string"
  end

  test "uses matching request requirements for note creation", %{index: index} do
    response = DataCase.endpoint_conn(:get, "/openapi.json", nil, index)
    document = JSON.decode!(response.resp_body)

    request_schema =
      get_in(document, [
        "paths",
        "/vaults/{vault_id}/notes",
        "post",
        "requestBody",
        "content",
        "application/json",
        "schema"
      ])

    tool = Enum.find(Operations.all(), &(&1.name == "create_note"))
    component = document["components"]["schemas"]["NoteInput"]

    assert request_schema["$ref"] == "#/components/schemas/NoteInput"
    assert tool.inputSchema.required == ["vault_id", "body"]

    assert ["vault_id" | Map.keys(component["properties"])] |> Enum.sort() ==
             Map.keys(tool.inputSchema.properties) |> Enum.sort()
  end

  test "uses the same fields and requirements for every shared operation", %{index: index} do
    document =
      :get
      |> DataCase.endpoint_conn("/openapi.json", nil, index)
      |> Map.fetch!(:resp_body)
      |> JSON.decode!()

    operations =
      document["paths"]
      |> Enum.flat_map(fn {_path, path_item} ->
        path_item
        |> Map.values()
        |> Enum.filter(&is_map/1)
      end)
      |> Map.new(&{&1["operationId"], &1})

    Enum.each(Operations.all(), fn tool ->
      operation = Map.fetch!(operations, tool.name)
      {properties, required} = operation_contract(operation, document)

      assert Enum.sort(properties) == tool.inputSchema.properties |> Map.keys() |> Enum.sort(),
             "property mismatch for #{tool.name}"

      assert Enum.sort(required) == Enum.sort(tool.inputSchema.required),
             "requirement mismatch for #{tool.name}"
    end)
  end

  defp operation_contract(operation, document) do
    parameters = Map.get(operation, "parameters", [])
    parameter_properties = Enum.map(parameters, & &1["name"])
    required_parameters = parameters |> Enum.filter(& &1["required"]) |> Enum.map(& &1["name"])

    body_schema =
      get_in(operation, ["requestBody", "content", "application/json", "schema"])
      |> resolve_schema(document)

    body_properties = body_schema |> Map.get("properties", %{}) |> Map.keys()
    body_required = Map.get(body_schema, "required", [])

    {Enum.uniq(parameter_properties ++ body_properties),
     Enum.uniq(required_parameters ++ body_required)}
  end

  defp resolve_schema(nil, _document), do: %{}

  defp resolve_schema(%{"$ref" => "#/components/schemas/" <> name}, document),
    do: document["components"]["schemas"][name]

  defp resolve_schema(schema, _document), do: schema
end
