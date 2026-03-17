class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :actor, class_name: "User"
  belongs_to :notifiable, polymorphic: true

  enum :event_type, { reply_to_post: 0, reply_in_thread: 1, mention: 2, moderation: 3 }

  def read?
    read_at.present?
  end
end
