class CreateCategories < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE TABLE categories (
        id SMALLINT PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        CONSTRAINT categories_name_unique UNIQUE (name)
      )
    SQL
    execute "INSERT INTO categories (id, name) VALUES (1, 'Other')"
  end

  def down
    drop_table :categories
  end
end
