require "test_helper"

class UserBanTest < ActiveSupport::TestCase
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user   = User.create!(email: "banned@example.com", name: "Banned User",
                           password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @mod    = User.create!(email: "mod@example.com", name: "Moderator",
                           password: "pass123", password_confirmation: "pass123", provider_id: 3)
    @reason = BanReason.create!(name: "Spam")
  end

  test "valid with user, reason, banned_until, and banned_by" do
    ban = UserBan.new(user: @user, ban_reason: @reason, banned_until: 1.day.from_now,
                      banned_by: @mod)
    assert ban.valid?
  end

  test "before_validation sets banned_from to now when blank" do
    ban = UserBan.new(user: @user, ban_reason: @reason, banned_until: 1.day.from_now,
                      banned_by: @mod)
    ban.valid?
    assert_not_nil ban.banned_from
  end

  test "invalid without banned_until" do
    ban = UserBan.new(user: @user, ban_reason: @reason, banned_by: @mod)
    assert_not ban.valid?
    assert_includes ban.errors[:banned_until], "can't be blank"
  end

  test "invalid when banned_until is not after banned_from" do
    ban = UserBan.new(user: @user, ban_reason: @reason, banned_by: @mod,
                      banned_from: Time.current, banned_until: 1.hour.ago)
    assert_not ban.valid?
    assert_includes ban.errors[:banned_until], "must be after banned from"
  end

  test "invalid without a user" do
    ban = UserBan.new(ban_reason: @reason, banned_until: 1.day.from_now, banned_by: @mod)
    assert_not ban.valid?
  end

  test "invalid without a ban_reason" do
    ban = UserBan.new(user: @user, banned_until: 1.day.from_now, banned_by: @mod)
    assert_not ban.valid?
  end

  test "invalid without banned_by on create" do
    ban = UserBan.new(user: @user, ban_reason: @reason, banned_until: 1.day.from_now)
    assert_not ban.valid?
    assert_includes ban.errors[:banned_by], "can't be blank"
  end
end
