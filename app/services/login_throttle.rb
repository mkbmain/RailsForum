class LoginThrottle
  MAX_ATTEMPTS = 5
  WINDOW       = 10.minutes

  def initialize(ip)
    @key = "login_attempts:#{ip}"
  end

  def throttled?
    attempts >= MAX_ATTEMPTS
  end

  def record_failure!
    written = Rails.cache.write(@key, 1, expires_in: WINDOW, unless_exist: true)
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
