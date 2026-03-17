require "test_helper"

class BansControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @creator = User.create!(email: "creator@example.com", name: "Creator",
                            password: "pass123", password_confirmation: "pass123",
                            provider_id: 3)
    @sub_admin = User.create!(email: "sub@example.com", name: "Sub",
                              password: "pass123", password_confirmation: "pass123",
                              provider_id: 3)
    @sub_admin.roles << Role.find_by!(name: Role::SUB_ADMIN)
    @admin = User.create!(email: "admin@example.com", name: "Admin",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @admin.roles << Role.find_by!(name: Role::ADMIN)
    BanReason.find_or_create_by!(name: "Spam")
    @ban_reason = BanReason.find_by!(name: "Spam")
  end

  test "GET /users/:user_id/bans/new requires login" do
    get new_user_ban_path(@creator)
    assert_redirected_to login_path
  end

  test "GET /users/:user_id/bans/new forbidden for creator-only user" do
    post login_path, params: { email: "creator@example.com", password: "pass123" }
    get new_user_ban_path(@creator)
    assert_redirected_to root_path
  end

  test "GET /users/:user_id/bans/new renders form for sub_admin" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    get new_user_ban_path(@creator)
    assert_response :success
  end

  test "GET /users/:user_id/bans/new forbidden when sub_admin targets another sub_admin" do
    other_sub = User.create!(email: "sub2@example.com", name: "Sub2",
                              password: "pass123", password_confirmation: "pass123",
                              provider_id: 3)
    other_sub.roles << Role.find_by!(name: Role::SUB_ADMIN)
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    get new_user_ban_path(other_sub)
    assert_redirected_to root_path
  end

  test "POST /users/:user_id/bans creates ban as sub_admin" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    assert_difference "UserBan.count", 1 do
      post user_bans_path(@creator),
           params: { duration_hours: "24", ban_reason_id: @ban_reason.id }
    end
    assert_redirected_to root_path
    ban = UserBan.last
    assert_equal @creator.id, ban.user_id
    assert_equal @sub_admin.id, ban.banned_by_id
    assert_in_delta 24.hours.from_now.to_i, ban.banned_until.to_i, 5
  end

  test "POST /users/:user_id/bans rejects sub_admin ban over 48 hours" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    assert_no_difference "UserBan.count" do
      post user_bans_path(@creator),
           params: { duration_hours: "72", ban_reason_id: @ban_reason.id }
    end
    assert_redirected_to new_user_ban_path(@creator)
    assert_match /48 hours maximum/, flash[:alert]
  end

  test "POST /users/:user_id/bans allows admin to ban over 48 hours" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_difference "UserBan.count", 1 do
      post user_bans_path(@creator),
           params: { duration_hours: "200", ban_reason_id: @ban_reason.id }
    end
    assert_redirected_to root_path
  end

  test "POST /users/:user_id/bans rejects duration less than 1 hour" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    assert_no_difference "UserBan.count" do
      post user_bans_path(@creator),
           params: { duration_hours: "0", ban_reason_id: @ban_reason.id }
    end
    assert_redirected_to new_user_ban_path(@creator)
    assert_match /at least 1 hour/, flash[:alert]
  end

  test "POST /users/:user_id/bans rejects invalid ban_reason_id" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    assert_no_difference "UserBan.count" do
      post user_bans_path(@creator),
           params: { duration_hours: "24", ban_reason_id: 99999 }
    end
    assert_redirected_to new_user_ban_path(@creator)
    assert_match /valid ban reason/, flash[:alert]
  end
end
