defmodule MarkdowWeb.ErrorJSON do
  @moduledoc false

  @spec render(String.t(), map()) :: %{error: String.t()}
  def render("500.json", _assigns), do: %{error: "operation_failed"}

  def render(template, _assigns) do
    error =
      template
      |> Phoenix.Controller.status_message_from_template()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    %{error: error}
  end
end
