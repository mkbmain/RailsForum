class CreateNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :notifications do |t|
      t.references :user,  null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.references :notifiable, polymorphic: true, null: false
      t.integer :event_type, limit: 2, null: false
      t.datetime :read_at
      t.timestamps
    end

    # Partial index for fast unread counts — only indexes unread rows
    add_index :notifications, :user_id,
              where: "read_at IS NULL",
              name: "index_notifications_on_user_id_unread"

    # Index for 24-hour reply_in_thread deduplication query
    add_index :notifications,
              [:user_id, :notifiable_id, :notifiable_type, :event_type, :created_at],
              name: "index_notifications_on_dedup_fields"
  end
end
