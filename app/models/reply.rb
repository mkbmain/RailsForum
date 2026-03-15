class Reply < ApplicationRecord
  belongs_to :post
  belongs_to :user

  validates :body, presence: true, length: { maximum: 1000 }

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
