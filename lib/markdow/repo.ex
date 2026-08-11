defmodule Markdow.Repo do
  use Ecto.Repo,
    otp_app: :markdow,
    adapter: Ecto.Adapters.Postgres
end
