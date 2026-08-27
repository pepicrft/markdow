defmodule Markdow.OAuth.ResourceOwners do
  @moduledoc """
  Boruta's resource owner context, deliberately empty.

  Markdow exposes exactly one Boruta grant, `client_credentials`, which has no
  resource owner by definition. The flows that would consult this module are the
  password and authorization code grants, and a registered client does not
  advertise them. Answering here would be the only way a client could act as a
  person without that person ever signing in, so every callback refuses.

  Human consent lives in the claim ceremony in `Markdow.AgentAuth` instead.
  """

  @behaviour Boruta.Oauth.ResourceOwners

  @impl Boruta.Oauth.ResourceOwners
  def get_by(_params),
    do: {:error, "Markdow does not authenticate resource owners through OAuth."}

  @impl Boruta.Oauth.ResourceOwners
  def check_password(_resource_owner, _password),
    do: {:error, "Markdow does not authenticate resource owners through OAuth."}

  @impl Boruta.Oauth.ResourceOwners
  def authorized_scopes(_resource_owner), do: []
end
