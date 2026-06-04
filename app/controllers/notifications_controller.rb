class NotificationsController < ApplicationController
  before_action :require_login

  def index
    # Load more than the display limit to account for grouping collapsing multiple records
    all_notifications = current_user.notifications
                                    .includes(:actor, :notifiable)
                                    .order(created_at: :desc)
                                    .limit(100)

    reply_notifiables = all_notifications.map(&:notifiable).grep(Reply)
    ActiveRecord::Associations::Preloader.new(records: reply_notifiables, associations: :post).call if reply_notifiables.any?

    valid = all_notifications.reject { |n| n.target_post.nil? }
    @notification_groups = build_notification_groups(valid).first(30)
    @unread_count = valid.count { |n| !n.read? }
  end

  def read
    notification = current_user.notifications.find_by(id: params[:id])
    notification&.mark_as_read!
    bust_notification_cache
    redirect_to notifications_path
  end

  def read_group
    ids = Array(params[:ids]).map(&:to_i).first(100)
    current_user.notifications.where(id: ids).update_all(read_at: Time.current)
    bust_notification_cache
    redirect_to notifications_path
  end

  def read_all
    current_user.notifications.unread.update_all(read_at: Time.current)
    bust_notification_cache
    redirect_to notifications_path
  end

  private

  # Groups consecutive reply_in_thread notifications for the same post into a single entry.
  # All other event types remain as individual items.
  # Returns an array of hashes, each either:
  #   { type: :single, notification: Notification }
  #   { type: :group, post: Post, actors: [User,...], ids: [Integer,...], unread: Boolean, created_at: Time }
  def build_notification_groups(notifications)
    groups = []
    notifications.each do |n|
      last = groups.last
      if n.reply_in_thread? && last&.dig(:type) == :group && last[:post].id == n.target_post.id
        last[:actors] |= [ n.actor ]
        last[:ids]    << n.id
        last[:unread] ||= !n.read?
      elsif n.reply_in_thread?
        groups << {
          type:       :group,
          post:       n.target_post,
          actors:     [ n.actor ],
          ids:        [ n.id ],
          unread:     !n.read?,
          created_at: n.created_at
        }
      else
        groups << { type: :single, notification: n }
      end
    end
    groups
  end
end
