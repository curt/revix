defmodule Revix.Repo.Migrations.AddLikeUriToLikes do
  use Ecto.Migration

  import Ecto.Query

  def up do
    alter table(:likes) do
      add :like_uri, :text, null: true
    end

    flush()

    rows =
      Revix.Repo.all(from(l in "likes", where: l.origin == "local", select: {l.id, l.author_uri}))

    for {id, author_uri} <- rows do
      %URI{scheme: scheme, host: host, port: port} = URI.parse(author_uri)

      default_port = if scheme == "https", do: 443, else: 80
      port_suffix = if port && port != default_port, do: ":#{port}", else: ""
      base = "#{scheme}://#{host}#{port_suffix}"
      like_uri = "#{base}/likes/#{id}"

      Revix.Repo.update_all(from(l in "likes", where: l.id == ^id), set: [like_uri: like_uri])
    end

    alter table(:likes) do
      modify :like_uri, :text, null: false
    end

    create unique_index(:likes, [:like_uri])
  end

  def down do
    drop_if_exists unique_index(:likes, [:like_uri])

    alter table(:likes) do
      remove :like_uri
    end
  end
end
