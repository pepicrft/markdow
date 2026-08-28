defmodule Markdow.Accounts.EmailVerificationToken do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Query

  alias Markdow.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :string
  @validity_in_minutes 15
  @random_size 32

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          token_hash: binary() | nil,
          context: String.t() | nil,
          sent_to: String.t() | nil,
          user_id: String.t() | nil
        }

  schema "user_email_verification_tokens" do
    field(:token_hash, :binary, redact: true)
    field(:context, :string)
    field(:sent_to, :string)
    belongs_to(:user, User)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @spec build(User.t(), String.t()) :: {String.t(), t()}
  def build(%User{} = user, context \\ "verification") when is_binary(context) do
    token = :crypto.strong_rand_bytes(@random_size)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token_hash: digest(token),
       context: context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @spec verification_query(String.t()) :: {:ok, Ecto.Query.t()} | :error
  def verification_query(encoded_token), do: query(encoded_token, "verification")

  @spec login_query(String.t()) :: {:ok, Ecto.Query.t()} | :error
  def login_query(encoded_token), do: query(encoded_token, "login")

  defp query(encoded_token, context) when is_binary(encoded_token) and is_binary(context) do
    with {:ok, token} <- Base.url_decode64(encoded_token, padding: false) do
      query =
        from(token_record in __MODULE__,
          join: user in assoc(token_record, :user),
          where: token_record.token_hash == ^digest(token),
          where: token_record.context == ^context,
          where: token_record.inserted_at > ago(@validity_in_minutes, "minute"),
          where: token_record.sent_to == user.email,
          select: {user, token_record}
        )

      {:ok, query}
    end
  end

  defp query(_encoded_token, _context), do: :error

  defp digest(value), do: :crypto.hash(:sha256, value)
end
