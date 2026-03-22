class BanChecker
  def initialize(user)
    @user = user
  end

  def banned?
    active_ban.present?
  end

  def banned_until
    active_ban&.banned_until
  end

  def ban_reason
    active_ban&.ban_reason&.name
  end

  private

  def active_ban
    @active_ban ||= @user.user_bans
                         .where("banned_until >= ?", Time.current)
                         .order(banned_until: :desc)
                         .first
  end
end
