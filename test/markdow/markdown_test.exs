defmodule Markdow.MarkdownTest do
  use ExUnit.Case, async: true

  alias Markdow.Markdown

  test "extracts common Obsidian frontmatter, title, tags, and wikilinks" do
    body = """
    ---
    title: Project map
    tags:
      - maps
      - work
    ---
    # Ignored heading

    See [[Architecture#Storage|the storage design]] and [[Daily note]].
    [[Architecture]] is intentionally repeated.
    """

    parsed = Markdown.parse("project-map", body)

    assert parsed.title == "Project map"
    assert parsed.path == "project-map"
    assert parsed.tags == ["maps", "work"]

    assert parsed.links == [
             %{
               target: "architecture",
               context: "See [[Architecture#Storage|the storage design]] and [[Daily note]]."
             },
             %{
               target: "daily note",
               context: "See [[Architecture#Storage|the storage design]] and [[Daily note]]."
             }
           ]
  end

  test "accepts JSON frontmatter and explicit index fields" do
    body = """
    ---
    {"title":"From JSON","tags":["one","two"]}
    ---
    Body
    """

    parsed =
      Markdown.parse("fallback", body,
        title: "Explicit title",
        path: "projects/explicit",
        metadata: %{status: "active"}
      )

    assert parsed.title == "Explicit title"
    assert parsed.path == "projects/explicit"
    assert parsed.metadata["status"] == "active"
    assert parsed.tags == ["one", "two"]
  end

  test "derives a readable title when metadata and headings are absent" do
    assert Markdown.parse("daily_first-note", "Plain body").title == "Daily First Note"
  end
end
