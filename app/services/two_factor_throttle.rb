class TwoFactorThrottle
  def initialize(user_id)
    @key     = "2fa_attempts:#{user_id}"
    @max     = Rails.application.config.x.two_factor_max_attempts
    @window  = Rails.application.config.x.two_factor_lockout_minutes.minutes
  end

  def throttled?
    attempts >= @max
  end

  def record_failure!
    written = Rails.cache.write(@key, 1, expires_in: @window, unless_exist: true)
    Rails.cache.increment(@key) unless written
  end

  def clear!
    Rails.cache.delete(@key)
  end

  private

  def attempts
    Rails.cache.read(@key).to_i
  end
end
