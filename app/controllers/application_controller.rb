class ApplicationController < ActionController::Base
  include Moderatable
  helper_method :current_user, :logged_in?, :can_moderate?

  before_action :check_session_timeout, if: :logged_in?
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

      if turbo_frame_request? || request.format.turbo_stream? || request.format.json?
        return head :unauthorized
      else
        redirect_to login_path, alert: "Your session has expired. Please log in again."
        return
      end
    end
  end

  def touch_session
    return unless session[:user_id].present? && session_timeout_minutes > 0
    session[:last_active_at] = Time.current.to_i
  end
end
