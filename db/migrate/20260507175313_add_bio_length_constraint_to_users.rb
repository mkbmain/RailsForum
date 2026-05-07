class AddBioLengthConstraintToUsers < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :users, "char_length(bio) <= 500", name: "users_bio_max_length"
  end

  def down
    remove_check_constraint :users, name: "users_bio_max_length"
  end
end
