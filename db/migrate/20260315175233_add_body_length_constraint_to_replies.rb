class AddBodyLengthConstraintToReplies < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :replies, "char_length(body) <= 1000", name: "replies_body_max_length"
  end
end
