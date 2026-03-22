class AddLowerNameIndexToUsers < ActiveRecord::Migration[8.1]
  def change
    add_index :users, "LOWER(name)", name: "index_users_on_lower_name"
  end
end
