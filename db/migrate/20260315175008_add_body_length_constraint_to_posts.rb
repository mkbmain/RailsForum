class AddBodyLengthConstraintToPosts < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :posts, "char_length(body) <= 1000", name: "posts_body_max_length"
  end
end
