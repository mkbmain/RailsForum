class Reaction < ApplicationRecord
  ALLOWED_REACTIONS = %w[👍 ❤️ 😂 😮].freeze

  belongs_to :user
  belongs_to :post

  validates :emoji, presence: true, inclusion: { in: ALLOWED_REACTIONS }
  validates :user_id, uniqueness: { scope: :post_id, message: "has already reacted to this post" }
end
