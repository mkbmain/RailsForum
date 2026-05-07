require "test_helper"

class TwoFactorThrottleTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @throttle = TwoFactorThrottle.new(42)
  end

  teardown do
    Rails.cache.clear
  end

  test "not throttled with zero failures" do
    assert_not @throttle.throttled?
  end

  test "not throttled below the limit" do
    (Rails.application.config.x.two_factor_max_attempts - 1).times { @throttle.record_failure! }
    assert_not @throttle.throttled?
  end

  test "throttled at the limit" do
    Rails.application.config.x.two_factor_max_attempts.times { @throttle.record_failure! }
    assert @throttle.throttled?
  end

  test "clear! resets the counter" do
    Rails.application.config.x.two_factor_max_attempts.times { @throttle.record_failure! }
    @throttle.clear!
    assert_not @throttle.throttled?
  end

  test "separate user IDs are tracked independently" do
    other = TwoFactorThrottle.new(99)
    Rails.application.config.x.two_factor_max_attempts.times { @throttle.record_failure! }
    assert @throttle.throttled?
    assert_not other.throttled?
  end
end
