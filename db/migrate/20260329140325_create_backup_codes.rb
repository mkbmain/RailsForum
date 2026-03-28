class CreateBackupCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_codes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string     :digest, null: false
      t.datetime   :used_at
      t.datetime   :created_at, null: false
    end

    add_index :backup_codes, [ :user_id, :digest ], unique: true
  end
end
