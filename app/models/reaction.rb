class Reaction < ApplicationRecord
  ALLOWED_REACTIONS = %w[👍 ❤️ 😂 😮].freeze

  belongs_to :user
  belongs_to :reactionable, polymorphic: true

  validates :emoji, presence: true, inclusion: { in: ALLOWED_REACTIONS }
  validates :user_id, uniqueness: { scope: [ :reactionable_type, :reactionable_id ],
                                    message: "has already reacted" }
end
