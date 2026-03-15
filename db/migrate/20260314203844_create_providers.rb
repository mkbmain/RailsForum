class CreateProviders < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE TABLE providers (
        id SMALLINT PRIMARY KEY,
        name VARCHAR(50) NOT NULL
      )
    SQL
  end

  def down
    drop_table :providers
  end
end
