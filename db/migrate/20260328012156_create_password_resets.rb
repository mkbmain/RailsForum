class CreatePasswordResets < ActiveRecord::Migration[8.1]
  def change
    create_table :password_resets do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :token, null: false
      t.datetime :created_at, null: false
      t.datetime :last_sent_at
    end

    add_index :password_resets, :token, unique: true
  end
end
