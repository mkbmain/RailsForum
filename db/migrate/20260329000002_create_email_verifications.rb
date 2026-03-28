class CreateEmailVerifications < ActiveRecord::Migration[8.1]
  def change
    create_table :email_verifications do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string     :token, null: false
      t.datetime   :created_at, null: false
      t.datetime   :last_sent_at
    end

    add_index :email_verifications, :token, unique: true
  end
end
