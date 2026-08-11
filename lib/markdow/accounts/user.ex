defmodule Markdow.Accounts.User do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{
          id: String.t(),
          email: String.t(),
          name: String.t() | nil,
          hashed_password: String.t() | nil,
          signed_up_by_agent: boolean(),
          email_verified_at: DateTime.t() | nil
        }

  schema "users" do
    field(:email, :string)
    field(:name, :string)
    field(:hashed_password, :string, redact: true)
    field(:password, :string, virtual: true, redact: true)
    field(:signed_up_by_agent, :boolean, default: false)
    field(:email_verified_at, :utc_datetime_usec)

    has_many(:vaults, Markdow.Accounts.Vault)

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:id, :email, :name])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:id, :email])
    |> validate_format(:id, ~r/^[A-Za-z0-9][A-Za-z0-9._-]*$/)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> unique_constraint(:email)
  end

  def agent_signup_changeset(user, attrs) do
    user
    |> cast(attrs, [:id, :email, :name, :password])
    |> update_change(:email, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:id, :email, :name, :password])
    |> validate_format(:id, ~r/^[A-Za-z0-9][A-Za-z0-9._-]*$/)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> validate_length(:name, min: 1, max: 160)
    |> validate_length(:password, min: 12, max: 72)
    |> unique_constraint(:email)
    |> put_change(:signed_up_by_agent, true)
    |> hash_password()
  end

  def valid_password?(%__MODULE__{hashed_password: hash}, password)
      when is_binary(hash) and is_binary(password) and byte_size(password) > 0 and
             byte_size(password) <= 72,
      do: Argon2.verify_pass(password, hash)

  def valid_password?(_user, _password) do
    Argon2.no_user_verify()
    false
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      password when is_binary(password) and changeset.valid? ->
        changeset
        |> put_change(:hashed_password, Argon2.hash_pwd_salt(password))
        |> delete_change(:password)

      _password ->
        changeset
    end
  end
end
