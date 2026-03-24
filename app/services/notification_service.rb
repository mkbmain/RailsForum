# NotificationService — handles all in-app notification fan-out.
#
# Designed as a clean boundary: callers invoke class methods here.
# In future, callers can publish to an event bus instead, with no other
# changes required in the rest of the app.
class NotificationService
  def self.reply_created(reply, current_user:)
    actor             = current_user
    post              = reply.post
    already_notified  = Set.new

    # 1. reply_to_post — notify post owner
    if post.user != actor
      Notification.create!(
        user:       post.user,
        actor:      actor,
        notifiable: reply,
        event_type: :reply_to_post
      )
      already_notified.add(post.user.id)
    end

    # 2. reply_in_thread — notify prior participants (deduplicated per 24h)
    reply_ids_in_post = post.replies.pluck(:id)
    recent_thread_notified_ids = Notification
      .where(notifiable_type: "Reply", notifiable_id: reply_ids_in_post, event_type: :reply_in_thread)
      .where("created_at > ?", 24.hours.ago)
      .pluck(:user_id)

    excluded_ids = [ actor.id ] + already_notified.to_a + recent_thread_notified_ids

    participant_ids = post.replies
                         .where.not(id: reply.id)
                         .where.not(user_id: excluded_ids)
                         .distinct
                         .pluck(:user_id)

    participant_ids.each do |uid|
      Notification.create!(
        user_id:          uid,
        actor_id:         actor.id,
        notifiable_type:  "Reply",
        notifiable_id:    reply.id,
        event_type:       :reply_in_thread
      )
      already_notified.add(uid)
    end

    # 3. mention — parse @username patterns
    reply.body.scan(/@(\w+)/i).flatten.uniq.each do |username|
      mentioned = User.find_by_mention_handle(username)
      next unless mentioned
      next if mentioned == actor
      next if already_notified.include?(mentioned.id)

      Notification.create!(
        user:       mentioned,
        actor:      actor,
        notifiable: reply,
        event_type: :mention
      )
      already_notified.add(mentioned.id)
    end
  end

  def self.content_removed(content, removed_by:)
    return if content.user == removed_by

    Notification.create!(
      user:       content.user,
      actor:      removed_by,
      notifiable: content,
      event_type: :moderation
    )
  end
end
