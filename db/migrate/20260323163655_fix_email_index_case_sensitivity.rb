class FixEmailIndexCaseSensitivity < ActiveRecord::Migration[8.1]
  def up
    remove_index :users, :email, name: "index_users_on_email"
    execute "CREATE UNIQUE INDEX index_users_on_lower_email ON users (LOWER(email))"
  end

  def down
    execute "DROP INDEX index_users_on_lower_email"
    add_index :users, :email, unique: true, name: "index_users_on_email"
  end
end
