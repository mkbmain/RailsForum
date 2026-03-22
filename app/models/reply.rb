class Reply < ApplicationRecord
  belongs_to :post
  belongs_to :user
  belongs_to :removed_by, class_name: "User", optional: true

  scope :visible, -> { where(removed_at: nil) }

  has_many :reactions, as: :reactionable, dependent: :destroy
  has_many :flags, -> { where(content_type_id: ContentType::CONTENT_REPLY) },
           class_name: "Flag", foreign_key: :flaggable_id, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy

  validates :body, presence: true, length: { maximum: 1000 }

  def removed? = removed_at.present?

  def edited?
    last_edited_at != created_at
  end

  after_create_commit { update_column(:last_edited_at, created_at) }
  after_create  :update_post_last_replied_at
  after_destroy :recalculate_post_last_replied_at

  private

  def update_post_last_replied_at
    if post.last_replied_at.nil? || created_at > post.last_replied_at
      post.update_column(:last_replied_at, created_at)
    end
  end

  def recalculate_post_last_replied_at
    post.update_column(:last_replied_at, post.replies.maximum(:created_at))
  end
end
