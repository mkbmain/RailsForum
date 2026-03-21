class NotificationsController < ApplicationController
  before_action :require_login

  def index
    @notifications = current_user.notifications
                                  .includes(:actor, :notifiable)
                                  .order(created_at: :desc)
                                  .limit(30)
    reply_notifiables = @notifications.map(&:notifiable).grep(Reply)
    ActiveRecord::Associations::Preloader.new(records: reply_notifiables, associations: :post).call if reply_notifiables.any?
    @unread_count  = current_user.notifications.unread.count
  end

  def read
    notification = current_user.notifications.find_by(id: params[:id])
    notification&.mark_as_read!
    redirect_to notifications_path
  end

  def read_all
    current_user.notifications.unread.update_all(read_at: Time.current)
    redirect_to notifications_path
  end
end
