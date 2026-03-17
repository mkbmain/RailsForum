class ApplicationController < ActionController::Base
  include Moderatable
  helper_method :current_user, :logged_in?, :can_moderate?

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
end
