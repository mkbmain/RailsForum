require "test_helper"

class EmailVerificationTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "ev@example.com", name: "EV User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL
    )
  end

  test "expired? returns false when 23 hours old" do
    ev = travel_to(23.hours.ago) { @user.create_email_verification!(last_sent_at: Time.current) }
    assert_not ev.expired?
  end

  test "expired? returns true when 25 hours old" do
    ev = travel_to(25.hours.ago) { @user.create_email_verification!(last_sent_at: Time.current) }
    assert ev.expired?
  end

  test "on_cooldown? returns false when last_sent_at is nil" do
    ev = @user.create_email_verification!(last_sent_at: nil)
    assert_not ev.on_cooldown?
  end

  test "on_cooldown? returns true when last_sent_at is 2 minutes ago" do
    ev = @user.create_email_verification!(last_sent_at: 2.minutes.ago)
    assert ev.on_cooldown?
  end

  test "on_cooldown? returns false when last_sent_at is 4 minutes ago" do
    ev = @user.create_email_verification!(last_sent_at: 4.minutes.ago)
    assert_not ev.on_cooldown?
  end
end
