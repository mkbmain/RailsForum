module Bannable
  extend ActiveSupport::Concern

  private

  # Depends on require_login having already run (current_user is guaranteed non-nil).
  def check_not_banned
    checker = BanChecker.new(current_user)
    if checker.banned?
      flash[:alert] = "You are banned until #{checker.banned_until.strftime("%B %-d, %Y")}. Reason: #{checker.ban_reason}."
      redirect_to ban_redirect_path
    end
  end

  def ban_redirect_path
    root_path
  end
end
