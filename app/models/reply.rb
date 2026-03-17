class Reply < ApplicationRecord
  belongs_to :post
  belongs_to :user
  belongs_to :removed_by, class_name: "User", optional: true

  scope :visible, -> { where(removed_at: nil) }

  validates :body, presence: true, length: { maximum: 1000 }

  def removed? = removed_at.present?

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
