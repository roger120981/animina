defmodule Animina.Repo.Migrations.AddCity do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    create table(:geo_data_cities, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("uuid_generate_v4()"), primary_key: true
      add :name, :citext, null: false
      add :zip_code, :text, null: false
      add :county, :citext, null: false
      add :federal_state, :citext, null: false
      add :lat, :float, null: false
      add :lon, :float, null: false
    end

    create unique_index(:geo_data_cities, [:zip_code],
             name: "geo_data_cities_unique_zip_code_index"
           )
  end

  def down do
    drop_if_exists unique_index(:geo_data_cities, [:zip_code],
                     name: "geo_data_cities_unique_zip_code_index"
                   )

    drop table(:geo_data_cities)
  end
end
