defmodule Revix.ActivityPub.TagUri do
  def generate(type) do
    id = Revix.Ecto.Base58Id.autogenerate()
    authority = System.get_env("REVIX_HOST", "revix")
    {id, "tag:#{authority},#{Date.utc_today()}:#{type}:#{id}"}
  end
end
