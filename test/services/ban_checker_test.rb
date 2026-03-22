require "test_helper"

class BanCheckerTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user   = User.create!(email: "bc@example.com", name: "Ban Checker",
                           password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @reason = BanReason.create!(name: "Spam")
  end

  test "banned? is false when user has no bans" do
    assert_not BanChecker.new(@user).banned?
  end

  test "banned? is true when user has an active ban" do
    UserBan.create!(user: @user, ban_reason: @reason, banned_until: 1.day.from_now,
                    banned_by: @user)
    assert BanChecker.new(@user).banned?
  end

  test "banned? is false when all bans are expired" do
    UserBan.create!(user: @user, ban_reason: @reason, banned_from: 2.days.ago, banned_until: 1.day.ago,
                    banned_by: @user)
    assert_not BanChecker.new(@user).banned?
  end

  test "banned_until returns nil when not banned" do
    assert_nil BanChecker.new(@user).banned_until
  end

  test "banned_until returns the expiry of the active ban" do
    expiry = 3.days.from_now
    UserBan.create!(user: @user, ban_reason: @reason, banned_until: expiry,
                    banned_by: @user)
    assert_equal expiry.to_i, BanChecker.new(@user).banned_until.to_i
  end

  test "banned_until returns the latest expiry when multiple active bans exist" do
    UserBan.create!(user: @user, ban_reason: @reason, banned_until: 1.day.from_now,
                    banned_by: @user)
    later = 5.days.from_now
    UserBan.create!(user: @user, ban_reason: @reason, banned_until: later,
                    banned_by: @user)
    assert_equal later.to_i, BanChecker.new(@user).banned_until.to_i
  end

  test "expired ban does not make user appear banned" do
    travel_to 2.days.ago do
      UserBan.create!(user: @user, ban_reason: @reason, banned_until: 1.day.from_now,
                      banned_by: @user)
    end
    assert_not BanChecker.new(@user).banned?
  end

  test "ban_reason returns the reason name of the active ban" do
    UserBan.create!(user: @user, ban_reason: @reason, banned_until: 1.day.from_now,
                    banned_by: @user)
    assert_equal "Spam", BanChecker.new(@user).ban_reason
  end
end
