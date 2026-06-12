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
    notified_user_ids = []

    ActiveRecord::Base.transaction do
      # 1. reply_to_post — notify post owner
      if post.user != actor
        Notification.create!(
          user:       post.user,
          actor:      actor,
          notifiable: reply,
          event_type: :reply_to_post
        )
        already_notified.add(post.user.id)
        notified_user_ids << post.user.id
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

      unless participant_ids.empty?
        now = Time.current
        event_int = Notification.event_types[:reply_in_thread]
        rows = participant_ids.map do |uid|
          { user_id: uid, actor_id: actor.id, notifiable_type: "Reply", notifiable_id: reply.id,
            event_type: event_int, created_at: now, updated_at: now }
        end
        Notification.insert_all(rows)
        participant_ids.each { |uid| already_notified.add(uid) }
        notified_user_ids.concat(participant_ids)
      end

      # 3. mention — parse @username patterns (skip code blocks and inline code)
      body_without_code = reply.body
        .gsub(/```.*?```/m, "")
        .gsub(/~~~.*?~~~/m, "")
        .gsub(/`[^`]*`/, "")
      body_without_code.scan(/@(\w+)/i).flatten.uniq.each do |username|
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
        notified_user_ids << mentioned.id
      end
    end

    notified_user_ids.each { |uid| Rails.cache.delete("unread_notifs/#{uid}") }
  end

  def self.content_removed(content, removed_by:)
    return if content.user == removed_by

    Notification.create!(
      user:       content.user,
      actor:      removed_by,
      notifiable: content,
      event_type: :moderation
    )
    Rails.cache.delete("unread_notifs/#{content.user.id}")
  end
end
