class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest
      t.string :name, null: false
      t.string :avatar_url
      t.integer :provider_id, limit: 2, null: false, default: 3
      t.string :uid

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, [:provider_id, :uid], unique: true, where: "uid IS NOT NULL"
    add_foreign_key :users, :providers
  end
end
