class CreateUserBans < ActiveRecord::Migration[8.1]
  def change
    create_table :user_bans do |t|
      t.references :user,       null: false, foreign_key: true
      t.references :ban_reason, null: false, foreign_key: true
      t.datetime :banned_from,  null: false, default: -> { "now()" }
      t.datetime :banned_until, null: false
      t.timestamps
    end
    add_index :user_bans, [:user_id, :banned_until]
  end
end
