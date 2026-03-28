class ApplicationController < ActionController::Base
  include Moderatable
  helper_method :current_user, :logged_in?, :can_moderate?, :unread_notification_count

  before_action :check_session_timeout, if: -> { logged_in? || session[:awaiting_2fa].present? }
  after_action  :touch_session

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    redirect_to login_path, alert: "Please log in first." and return unless logged_in?
  end

  def session_timeout_minutes
    SESSION_TIMEOUT_MINUTES
  end

  def check_session_timeout
    return if session_timeout_minutes == 0

    unless session[:last_active_at]
      session[:last_active_at] = Time.current.to_i
      return
    end

    if Time.current.to_i - session[:last_active_at] > session_timeout_minutes * 60
      @current_user = nil
      reset_session

      if request.format.turbo_stream? || request.format.json?
        head :unauthorized
      else
        response.set_header("Turbo-Frame", "_top") if turbo_frame_request?
        redirect_to login_path, alert: "Your session has expired. Please log in again."
      end
    end
  end

  def touch_session
    active = session[:user_id].present? || session[:awaiting_2fa].present?
    return unless active && session_timeout_minutes > 0
    session[:last_active_at] = Time.current.to_i
  end

  def unread_notification_count
    return 0 unless logged_in?
    @unread_notification_count ||= current_user.notifications.unread.count
  end
end
