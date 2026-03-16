class CreateBanReasons < ActiveRecord::Migration[8.1]
  def change
    create_table :ban_reasons do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :ban_reasons, :name, unique: true
  end
end
