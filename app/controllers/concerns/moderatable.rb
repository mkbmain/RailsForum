module Moderatable
  extend ActiveSupport::Concern

  private

  def require_moderator
    redirect_to root_path, alert: "Not authorized." and return unless current_user&.moderator?
  end

  def require_admin
    redirect_to root_path, alert: "Not authorized." and return unless current_user&.admin?
  end

  def can_moderate?(target_user)
    return false unless current_user&.moderator?
    return false if current_user == target_user
    return false if target_user.admin?
    return true if current_user.admin?
    !target_user.sub_admin? && !target_user.admin?
  end
end
