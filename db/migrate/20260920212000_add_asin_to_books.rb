# frozen_string_literal: true

class AddAsinToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :asin, :string
    add_index :books, :asin
  end
end
