defmodule Revix.Schema do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      @primary_key {:id, Revix.Ecto.Base58Id, autogenerate: true}
      @foreign_key_type Revix.Ecto.Base58Id
      @timestamps_opts [type: :utc_datetime]
    end
  end
end
