class BansController < ApplicationController
  before_action :require_login
  before_action :require_moderator
  before_action :set_target_user
  before_action :check_hierarchy

  def new
    @ban = UserBan.new
    @ban_reasons = BanReason.all.order(:name)
    @max_hours = current_user.admin? ? nil : 48
  end

  def create
    duration_hours = params[:duration_hours].to_i
    if duration_hours < 1
      redirect_to new_user_ban_path(@target_user), alert: "Duration must be at least 1 hour."
      return
    end
    if !current_user.admin? && duration_hours > 48
      redirect_to new_user_ban_path(@target_user), alert: "Sub admins can ban for 48 hours maximum."
      return
    end
    ban_reason = BanReason.find_by(id: params[:ban_reason_id])
    unless ban_reason
      redirect_to new_user_ban_path(@target_user), alert: "Please select a valid ban reason."
      return
    end
    @ban = UserBan.new(
      user:         @target_user,
      ban_reason:   ban_reason,
      banned_by:    current_user,
      banned_until: Time.current + duration_hours.hours
    )
    if @ban.save
      redirect_to root_path, notice: "#{@target_user.name} has been banned."
    else
      @ban_reasons = BanReason.all.order(:name)
      @max_hours = current_user.admin? ? nil : 48
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_target_user
    @target_user = User.find(params[:user_id])
  end

  def check_hierarchy
    unless can_moderate?(@target_user)
      redirect_to root_path, alert: "Not authorized to ban this user." and return
    end
  end
end
