class AddLastRepliedAtToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :last_replied_at, :datetime
  end
end
