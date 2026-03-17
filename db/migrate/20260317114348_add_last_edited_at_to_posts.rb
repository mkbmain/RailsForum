class AddLastEditedAtToPosts < ActiveRecord::Migration[8.1]
  def up
    add_column :posts, :last_edited_at, :datetime, default: -> { "NOW()" }
    execute "UPDATE posts SET last_edited_at = created_at"
    change_column_null :posts, :last_edited_at, false
  end

  def down
    remove_column :posts, :last_edited_at
  end
end
