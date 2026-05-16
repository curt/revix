defmodule Revix.Media.Behaviour do
  alias Revix.Media.Image

  @callback create_image(attrs :: map()) ::
              {:ok, Image.t()} | {:error, Ecto.Changeset.t()}

  @callback attach_image_to_entry(
              entry_id :: String.t(),
              image_id :: String.t(),
              position :: non_neg_integer()
            ) ::
              {:ok, term()} | {:error, Ecto.Changeset.t()}

  @callback update_image(image :: Image.t(), attrs :: map()) ::
              {:ok, Image.t()} | {:error, Ecto.Changeset.t()}
end
