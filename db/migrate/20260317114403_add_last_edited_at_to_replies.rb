class AddLastEditedAtToReplies < ActiveRecord::Migration[8.1]
  def up
    add_column :replies, :last_edited_at, :datetime, default: -> { "NOW()" }
    execute "UPDATE replies SET last_edited_at = created_at"
    change_column_null :replies, :last_edited_at, false
  end

  def down
    remove_column :replies, :last_edited_at
  end
end
