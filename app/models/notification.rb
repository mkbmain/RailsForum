class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :actor, class_name: "User"
  belongs_to :notifiable, polymorphic: true

  enum :event_type, { reply_to_post: 0, reply_in_thread: 1, mention: 2, moderation: 3 }

  scope :unread, -> { where(read_at: nil) }
  scope :read,   -> { where.not(read_at: nil) }

  def read?
    read_at.present?
  end

  def mark_as_read!
    update(read_at: Time.current) unless read?
  end

  def target_post
    case notifiable
    when nil   then nil
    when Post  then notifiable
    when Reply then notifiable.post
    else raise ArgumentError, "Unknown notifiable type for target_post: #{notifiable.class}"
    end
  end
end
