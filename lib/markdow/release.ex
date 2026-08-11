defmodule Markdow.Release do
  @moduledoc false

  @app :markdow

  @spec migrate() :: [term()]
  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, result, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))

      result
    end
  end
end
