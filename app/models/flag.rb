class Flag < ApplicationRecord
  belongs_to :user
  belongs_to :content_type
  belongs_to :resolved_by, class_name: "User", optional: true

  enum :reason, { spam: 0, harassment: 1, misinformation: 2, other: 3 }

  scope :pending,  -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }

  validates :flaggable_id,    presence: true
  validates :reason,          presence: true
  validates :content_type_id, presence: true,
                              inclusion: { in: [ ContentType::CONTENT_POST, ContentType::CONTENT_REPLY ] }
  validates :user_id, uniqueness: { scope: [ :content_type_id, :flaggable_id ],
                                    message: "has already flagged this content" }

  # Resolves the flagged record. Returns nil if hard-deleted; returns record (possibly
  # soft-deleted) if it still exists.
  def flaggable
    case content_type_id
    when ContentType::CONTENT_POST  then Post.find_by(id: flaggable_id)
    when ContentType::CONTENT_REPLY then Reply.find_by(id: flaggable_id)
    end
  end
end
