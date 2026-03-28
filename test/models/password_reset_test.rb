require "test_helper"

class PasswordResetTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "pr@example.com", name: "PR User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL
    )
  end

  # expired?
  test "expired? returns false when 59 minutes old" do
    reset = travel_to(59.minutes.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    assert_not reset.expired?
  end

  test "expired? returns true when 61 minutes old" do
    reset = travel_to(61.minutes.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    assert reset.expired?
  end

  # reusable?
  test "reusable? returns true when 39 minutes old" do
    reset = travel_to(39.minutes.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    assert reset.reusable?
  end

  test "reusable? returns true at exact 40-minute boundary" do
    # Capture `now` then travel_to exactly 40 min before it; assert at exactly `now`.
    # Without freezing the assertion moment, sub-second drift between the travel_to
    # block and the assert call makes `created_at` land just before `40.minutes.ago`,
    # flipping the `>=` boundary to false.
    now = Time.current
    reset = travel_to(now - 40.minutes) { @user.create_password_reset!(last_sent_at: Time.current) }
    travel_to(now) do
      assert reset.reusable?
    end
  end

  test "reusable? returns false when 41 minutes old" do
    reset = travel_to(41.minutes.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    assert_not reset.reusable?
  end

  # on_cooldown?
  test "on_cooldown? returns false when last_sent_at is nil" do
    reset = @user.create_password_reset!(last_sent_at: nil)
    assert_not reset.on_cooldown?
  end

  test "on_cooldown? returns true when last_sent_at is 2 minutes ago" do
    reset = @user.create_password_reset!(last_sent_at: 2.minutes.ago)
    assert reset.on_cooldown?
  end

  test "on_cooldown? returns false when last_sent_at is 4 minutes ago" do
    reset = @user.create_password_reset!(last_sent_at: 4.minutes.ago)
    assert_not reset.on_cooldown?
  end
end
