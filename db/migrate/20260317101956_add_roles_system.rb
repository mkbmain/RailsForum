class AddRolesSystem < ActiveRecord::Migration[8.1]
  def change
    create_table :roles, id: :smallint do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :roles, :name, unique: true

    create_table :user_roles, id: :integer do |t|
      t.bigint  :user_id, null: false
      t.column  :role_id, :smallint, null: false
      t.datetime :created_at, null: false, default: -> { "now()" }
    end
    add_index :user_roles, [:user_id, :role_id], unique: true
    add_foreign_key :user_roles, :users, column: :user_id
    add_foreign_key :user_roles, :roles, column: :role_id

    add_column :posts, :removed_at,    :datetime
    add_column :posts, :removed_by_id, :bigint
    add_foreign_key :posts, :users, column: :removed_by_id

    add_column :replies, :removed_at,    :datetime
    add_column :replies, :removed_by_id, :bigint
    add_foreign_key :replies, :users, column: :removed_by_id

    add_column :user_bans, :banned_by_id, :bigint
    add_foreign_key :user_bans, :users, column: :banned_by_id
  end
end
