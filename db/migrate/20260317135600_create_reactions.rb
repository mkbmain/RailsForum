class CreateReactions < ActiveRecord::Migration[8.1]
  def change
    create_table :reactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :post, null: false, foreign_key: true
      t.string :emoji, limit: 10, null: false
      t.timestamps
    end

    add_index :reactions, [:user_id, :post_id], unique: true
  end
end
