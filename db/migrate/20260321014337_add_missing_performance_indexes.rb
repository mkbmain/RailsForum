class AddMissingPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    # Post.visible uses where(removed_at: nil) on every query
    add_index :posts, :removed_at, where: "removed_at IS NULL"

    # Posts index/search ORDER BY COALESCE(last_replied_at, created_at)
    add_index :posts, :last_replied_at

    # Composite for rate-limit COUNT queries (user_id + created_at range)
    add_index :posts, [ :user_id, :created_at ]

    # Reply.visible uses where(removed_at: nil) on every query
    add_index :replies, :removed_at, where: "removed_at IS NULL"

    # Composite for rate-limit COUNT queries (user_id + created_at range)
    add_index :replies, [ :user_id, :created_at ]
  end
end
