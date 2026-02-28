defmodule Revix.Uploaders.Validation do
  @doc """
  Validates that a file's extension is in `allowed_extensions` and that its
  content (magic bytes) matches one of `allowed_types`.

  `allowed_extensions` — list of lowercase extensions including the dot, e.g. ~w(.jpg .jpeg .png)
  `allowed_types`      — ExImageInfo type atoms, e.g. [:jpg, :gif, :png, :webp]
  """
  def validate_image(file, allowed_extensions, allowed_types) do
    extension = file.file_name |> Path.extname() |> String.downcase()

    with true <- extension in allowed_extensions,
         {:ok, bytes} <- File.read(file.path),
         type <- ExImageInfo.seems?(bytes),
         true <- type in allowed_types do
      :ok
    else
      _ -> {:error, "invalid file type"}
    end
  end
end
