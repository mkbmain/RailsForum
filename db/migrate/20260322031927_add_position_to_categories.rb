class AddPositionToCategories < ActiveRecord::Migration[8.1]
  def up
    add_column :categories, :position, :integer, limit: 2, null: false, default: 0

    execute <<~SQL
      UPDATE categories SET position = 1 WHERE id = 2;
      UPDATE categories SET position = 2 WHERE id = 3;
      UPDATE categories SET position = 3 WHERE id = 4;
    SQL

    change_column_default :categories, :position, from: 0, to: nil
  end

  def down
    remove_column :categories, :position
  end
end
