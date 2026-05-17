defmodule Revix.Repo.Migrations.AddSituationToPlaces do
  use Ecto.Migration

  def change do
    alter table(:places) do
      add :country, :text
      add :city, :text
      add :secondary, :text
    end

    create constraint(:places, :country_length_2,
             check: "country IS NULL OR char_length(country) = 2"
           )

    create constraint(:places, :city_requires_country,
             check: "city IS NULL OR country IS NOT NULL"
           )

    create constraint(:places, :secondary_requires_city,
             check: "secondary IS NULL OR (country IS NOT NULL AND city IS NOT NULL)"
           )
  end
end
