class CreateContentTypesAndFlags < ActiveRecord::Migration[8.1]
  def up
    create_table :content_types, id: :integer, force: :cascade do |t|
      t.string :name, limit: 50, null: false
    end

    execute <<~SQL
      INSERT INTO content_types (id, name) VALUES (1, 'Post'), (2, 'Reply');
    SQL

    create_table :flags, id: :integer, force: :cascade do |t|
      t.bigint  :user_id,          null: false
      t.integer :content_type_id,  null: false, limit: 2
      t.bigint  :flaggable_id,     null: false
      t.integer :reason,           null: false, limit: 2
      t.datetime :resolved_at
      t.bigint :resolved_by_id
      t.timestamps
    end

    add_index :flags, [ :user_id, :content_type_id, :flaggable_id ], unique: true,
              name: "index_flags_on_user_content_flaggable"
    add_index :flags, [ :content_type_id, :flaggable_id ],
              name: "index_flags_on_content_type_and_flaggable"
    add_index :flags, :created_at, where: "resolved_at IS NULL",
              name: "index_flags_pending_by_created_at"

    add_foreign_key :flags, :users, column: :user_id
    add_foreign_key :flags, :content_types, column: :content_type_id
    add_foreign_key :flags, :users, column: :resolved_by_id
  end

  def down
    drop_table :flags
    drop_table :content_types
  end
end
