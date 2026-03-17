class NotificationsController < ApplicationController
  before_action :require_login

  def index
    @notifications = current_user.notifications
                                  .includes(:actor, :notifiable)
                                  .order(created_at: :desc)
                                  .limit(30)
    @unread_count  = current_user.notifications.where(read_at: nil).count
  end

  def read
    notification = current_user.notifications.find_by(id: params[:id])
    notification&.update(read_at: Time.current)
    redirect_to notifications_path
  end

  def read_all
    current_user.notifications.where(read_at: nil).update_all(read_at: Time.current)
    redirect_to notifications_path
  end
end
