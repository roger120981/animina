defmodule Animina.Repo.Migrations.DropTranslations do
  @moduledoc """
  Removes flag and category translation tables.

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    drop_if_exists constraint(
      :traits_category_translations,
      "traits_category_translations_category_id_fkey"
    )

    drop_if_exists table(:traits_category_translations)

    drop_if_exists unique_index(
      :traits_flag_translations,
      [:name, :language, :flag_id],
      name: "traits_flag_translations_unique_name_index"
    )

    drop_if_exists unique_index(
      :traits_flag_translations,
      [:hashtag, :language],
      name: "traits_flag_translations_hashtag_index"
    )

    drop_if_exists constraint(
      :traits_flag_translations,
      "traits_flag_translations_flag_id_fkey"
    )

    drop table(:traits_flag_translations)
  end

  def down do
    create table(:traits_flag_translations, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :language, :text, null: false
      add :name, :citext, null: false
      add :hashtag, :citext, null: false

      add :flag_id,
          references(
            :traits_flags,
            column: :id,
            name: "traits_flag_translations_flag_id_fkey",
            type: :uuid,
            prefix: "public"
          )
    end

    create unique_index(
      :traits_flag_translations,
      [:hashtag, :language],
      name: "traits_flag_translations_hashtag_index"
    )

    create unique_index(
      :traits_flag_translations,
      [:name, :language, :flag_id],
      name: "traits_flag_translations_unique_name_index"
    )

    create table(:traits_category_translations, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :language, :text, null: false
      add :name, :citext, null: false
      add :category_id, :uuid
    end

    alter table(:traits_category_translations) do
      modify :category_id,
             references(
               :traits_categories,
               column: :id,
               name: "traits_category_translations_category_id_fkey",
               type: :uuid,
               prefix: "public"
             )
    end
  end
end
