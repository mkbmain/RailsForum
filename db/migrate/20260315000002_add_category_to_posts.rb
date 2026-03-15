class AddCategoryToPosts < ActiveRecord::Migration[8.0]
  def up
    add_column :posts, :category_id, :integer, limit: 2, null: false, default: 1
    add_foreign_key :posts, :categories, column: :category_id
    add_index :posts, :category_id
  end

  def down
    remove_index :posts, :category_id
    remove_foreign_key :posts, column: :category_id
    remove_column :posts, :category_id
  end
end
