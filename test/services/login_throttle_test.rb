require "test_helper"

class LoginThrottleTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    @throttle = LoginThrottle.new("1.2.3.4")
  end

  teardown do
    Rails.cache.clear
  end

  test "not throttled with zero failures" do
    assert_not @throttle.throttled?
  end

  test "not throttled below the limit" do
    (LoginThrottle::MAX_ATTEMPTS - 1).times { @throttle.record_failure! }
    assert_not @throttle.throttled?
  end

  test "throttled at the limit" do
    LoginThrottle::MAX_ATTEMPTS.times { @throttle.record_failure! }
    assert @throttle.throttled?
  end

  test "clear! resets the counter" do
    LoginThrottle::MAX_ATTEMPTS.times { @throttle.record_failure! }
    assert @throttle.throttled?
    @throttle.clear!
    assert_not @throttle.throttled?
  end

  test "separate IPs are tracked independently" do
    other = LoginThrottle.new("9.9.9.9")
    LoginThrottle::MAX_ATTEMPTS.times { @throttle.record_failure! }
    assert @throttle.throttled?
    assert_not other.throttled?
  end
end
