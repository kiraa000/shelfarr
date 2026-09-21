# frozen_string_literal: true

class CreateWatchedSeries < ActiveRecord::Migration[8.1]
  def change
    create_table :watched_series do |t|
      t.references :user, null: false, foreign_key: true
      t.string :collection_source, null: false, default: "hardcover"
      t.string :collection_id, null: false
      t.string :title, null: false
      t.json :book_types, null: false, default: []
      t.string :language
      t.boolean :enabled, null: false, default: true
      t.datetime :last_checked_at
      t.datetime :last_success_at
      t.text :last_error
      t.timestamps
    end

    add_index :watched_series,
      [ :user_id, :collection_source, :collection_id ],
      unique: true,
      name: "index_watched_series_on_user_and_collection"
    add_index :watched_series, :enabled
  end
end
