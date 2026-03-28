class AddTotpSecretToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :totp_secret, :string
  end
end
