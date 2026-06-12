class NotificationJob < ApplicationJob
  queue_as :default

  def perform(reply_id, actor_id)
    reply = Reply.find_by(id: reply_id)
    actor = User.find_by(id: actor_id)
    return unless reply && actor

    NotificationService.reply_created(reply, current_user: actor)
  end
end
