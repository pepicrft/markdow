defmodule Markdow.Markdown do
  @moduledoc "Extracts indexable metadata and wikilinks from Markdown notes."

  @frontmatter ~r/\A---\r?\n(?<metadata>.*?)\r?\n---(?:\r?\n|\z)/s
  @heading ~r/^#\s+(.+)$/m
  @wikilink ~r/\[\[([^\]]+)\]\]/

  @type parsed :: %{
          title: String.t(),
          path: String.t(),
          metadata: map(),
          tags: [String.t()],
          links: [%{target: String.t(), context: String.t()}]
        }

  @spec parse(String.t(), String.t(), keyword()) :: parsed()
  def parse(id, body, opts \\ []) do
    {frontmatter, content} = frontmatter(body)
    metadata = Map.merge(frontmatter, normalize_metadata(Keyword.get(opts, :metadata, %{})))

    %{
      title: title(id, content, metadata, Keyword.get(opts, :title)),
      path: Keyword.get(opts, :path, id),
      metadata: metadata,
      tags: tags(metadata),
      links: links(content)
    }
  end

  @spec links(String.t()) :: [%{target: String.t(), context: String.t()}]
  def links(body) do
    body
    |> String.split(~r/\R/)
    |> Enum.flat_map(fn line ->
      @wikilink
      |> Regex.scan(line, capture: :all_but_first)
      |> Enum.map(fn [target] ->
        %{target: normalize_link_target(target), context: String.trim(line)}
      end)
    end)
    |> Enum.reject(&(&1.target == ""))
    |> Enum.uniq_by(& &1.target)
  end

  @spec normalize_link_target(String.t()) :: String.t()
  def normalize_link_target(target) do
    target
    |> String.split("|", parts: 2)
    |> List.first()
    |> String.split("#", parts: 2)
    |> List.first()
    |> String.trim()
    |> Path.rootname(".md")
    |> String.downcase()
  end

  defp frontmatter(body) do
    case Regex.named_captures(@frontmatter, body) do
      %{"metadata" => raw} -> {decode_frontmatter(raw), Regex.replace(@frontmatter, body, "")}
      nil -> {%{}, body}
    end
  end

  defp decode_frontmatter(raw) do
    case JSON.decode(raw) do
      {:ok, metadata} when is_map(metadata) -> metadata
      _error -> decode_simple_yaml(raw)
    end
  end

  defp decode_simple_yaml(raw) do
    raw
    |> String.split(~r/\R/)
    |> Enum.reduce({%{}, nil}, &parse_metadata_line/2)
    |> elem(0)
  end

  defp parse_metadata_line(line, {metadata, list_key}) do
    cond do
      Regex.match?(~r/^\s*-\s+.+$/, line) and is_binary(list_key) ->
        [value] = Regex.run(~r/^\s*-\s+(.+)$/, line, capture: :all_but_first)
        {Map.update(metadata, list_key, [scalar(value)], &(&1 ++ [scalar(value)])), list_key}

      match = Regex.run(~r/^\s*([^:#]+):\s*(.*?)\s*$/, line, capture: :all_but_first) ->
        [key, value] = match
        key = String.trim(key)

        if value == "" do
          {Map.put(metadata, key, []), key}
        else
          {Map.put(metadata, key, scalar(value)), nil}
        end

      true ->
        {metadata, list_key}
    end
  end

  defp scalar("[" <> rest) do
    rest
    |> String.trim_trailing("]")
    |> String.split(",", trim: true)
    |> Enum.map(&scalar/1)
  end

  defp scalar(value) do
    value = value |> String.trim() |> String.trim_leading("\"") |> String.trim_trailing("\"")

    case value do
      "true" -> true
      "false" -> false
      "null" -> nil
      value -> value
    end
  end

  defp normalize_metadata(metadata) when is_map(metadata) do
    Map.new(metadata, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_metadata(_metadata), do: %{}

  defp title(id, content, metadata, explicit_title) do
    explicit_title || metadata["title"] || heading(content) || humanize(id)
  end

  defp heading(content) do
    case Regex.run(@heading, content, capture: :all_but_first) do
      [title] -> String.trim(title)
      nil -> nil
    end
  end

  defp humanize(id) do
    id
    |> Path.basename()
    |> String.replace(~r/[-_]+/, " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp tags(metadata) do
    metadata
    |> Map.get("tags", [])
    |> List.wrap()
    |> Enum.flat_map(fn
      tag when is_binary(tag) -> String.split(tag, ",", trim: true)
      _tag -> []
    end)
    |> Enum.map(fn tag -> tag |> String.trim() |> String.trim_leading("#") end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end
end
