require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @creator = User.create!(email: "creator@example.com", name: "Alice Creator",
                            password: "pass123", password_confirmation: "pass123",
                            provider_id: 3)
    @sub_admin = User.create!(email: "sub@example.com", name: "Bob Sub",
                              password: "pass123", password_confirmation: "pass123",
                              provider_id: 3)
    @sub_admin.roles << Role.find_by!(name: Role::SUB_ADMIN)
    @admin = User.create!(email: "admin@example.com", name: "Carol Admin",
                          password: "pass123", password_confirmation: "pass123",
                          provider_id: 3)
    @admin.roles << Role.find_by!(name: Role::ADMIN)
  end

  test "GET /admin/users redirects guest" do
    get admin_users_path
    assert_redirected_to login_path
  end

  test "GET /admin/users lists all users" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_users_path
    assert_response :success
    assert_match "Alice Creator", response.body
    assert_match "Bob Sub", response.body
    assert_match "Carol Admin", response.body
  end

  test "GET /admin/users filters by name (case-insensitive)" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_users_path, params: { q: "alice" }
    assert_response :success
    assert_match "Alice Creator", response.body
    assert_no_match "Bob Sub", response.body
  end

  test "GET /admin/users filters by email" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_users_path, params: { q: "sub@example" }
    assert_response :success
    assert_match "Bob Sub", response.body
    assert_no_match "Alice Creator", response.body
  end

  test "GET /admin/users/:id shows user header with email and role" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_user_path(@creator)
    assert_response :success
    assert_match "Alice Creator", response.body
    assert_match "creator@example.com", response.body
    assert_match "Creator", response.body
  end

  test "GET /admin/users/:id shows active ban in header" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    BanReason.find_or_create_by!(name: "Spam")
    ban_reason = BanReason.find_by!(name: "Spam")
    UserBan.create!(user: @creator, ban_reason: ban_reason, banned_by: @admin,
                    banned_from: Time.current, banned_until: 5.hours.from_now)
    get admin_user_path(@creator)
    assert_response :success
    assert_match "Banned until", response.body
  end

  test "GET /admin/users/:id posts tab shows all posts including removed" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    category = Category.find_or_create_by!(id: 2, name: "General") { |c| c.position = 1 }
    @creator.posts.create!(title: "Live Post", body: "body text here ok", category: category)
    removed = @creator.posts.create!(title: "Gone Post", body: "body text here ok", category: category)
    removed.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
    get admin_user_path(@creator), params: { tab: "posts" }
    assert_response :success
    assert_match "Live Post", response.body
    assert_match "Gone Post", response.body
    assert_match "Removed", response.body
  end

  test "GET /admin/users/:id replies tab shows all replies including removed" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    category = Category.find_or_create_by!(id: 2, name: "General") { |c| c.position = 1 }
    parent = @admin.posts.create!(title: "Parent Post", body: "body text here ok", category: category)
    parent.replies.create!(body: "live reply body ok", user: @creator)
    removed = parent.replies.create!(body: "removed reply body ok", user: @creator)
    removed.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
    get admin_user_path(@creator), params: { tab: "replies" }
    assert_response :success
    assert_match "live reply body ok", response.body
    assert_match "removed reply body ok", response.body
    assert_match "Parent Post", response.body
  end

  test "GET /admin/users/:id bans tab shows ban history" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    BanReason.find_or_create_by!(name: "Spam")
    ban_reason = BanReason.find_by!(name: "Spam")
    UserBan.create!(user: @creator, ban_reason: ban_reason, banned_by: @admin,
                    banned_from: Time.current, banned_until: 3.hours.from_now)
    get admin_user_path(@creator), params: { tab: "bans" }
    assert_response :success
    assert_match "Spam", response.body
    assert_match "Carol Admin", response.body
  end

  test "GET /admin/users/:id activity tab shows bans issued by a moderator" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    BanReason.find_or_create_by!(name: "Spam")
    ban_reason = BanReason.find_by!(name: "Spam")
    UserBan.create!(user: @creator, ban_reason: ban_reason, banned_by: @sub_admin,
                    banned_from: Time.current, banned_until: 3.hours.from_now)
    get admin_user_path(@sub_admin), params: { tab: "activity" }
    assert_response :success
    assert_match "Alice Creator", response.body
  end

  test "GET /admin/users/:id does not show activity tab for user with no moderation history" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_user_path(@creator)
    assert_response :success
    assert_no_match "Moderation Activity", response.body
  end

  test "GET /admin/users/:id sub_admin can view user detail" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    get admin_user_path(@creator)
    assert_response :success
  end

  test "GET /admin/users/:id creator cannot access admin panel" do
    post login_path, params: { email: "creator@example.com", password: "pass123" }
    get admin_user_path(@admin)
    assert_redirected_to root_path
  end

  test "PATCH promote grants sub_admin role to creator" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert_not @creator.sub_admin?
    patch promote_admin_user_path(@creator)
    assert_redirected_to admin_user_path(@creator)
    assert @creator.reload.sub_admin?
    assert_match /promoted/i, flash[:notice]
  end

  test "PATCH demote removes sub_admin role" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    assert @sub_admin.sub_admin?
    patch demote_admin_user_path(@sub_admin)
    assert_redirected_to admin_user_path(@sub_admin)
    assert_not @sub_admin.reload.sub_admin?
    assert_match /demoted/i, flash[:notice]
  end

  test "PATCH promote is forbidden for sub_admin actor" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch promote_admin_user_path(@creator)
    assert_redirected_to root_path
    assert_not @creator.reload.sub_admin?
  end

  test "PATCH demote is forbidden for sub_admin actor" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch demote_admin_user_path(@sub_admin)
    assert_redirected_to root_path
    assert @sub_admin.reload.sub_admin?
  end

  test "PATCH promote on self redirects with alert" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch promote_admin_user_path(@admin)
    assert_redirected_to admin_user_path(@admin)
    assert_match /cannot/i, flash[:alert]
  end

  test "PATCH promote on another admin redirects with alert" do
    other = User.create!(email: "a2@example.com", name: "Other Admin",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    other.roles << Role.find_by!(name: Role::ADMIN)
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch promote_admin_user_path(other)
    assert_redirected_to admin_user_path(other)
    assert_match /cannot/i, flash[:alert]
  end

  test "PATCH promote is idempotent when user is already sub_admin" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch promote_admin_user_path(@sub_admin)
    assert_redirected_to admin_user_path(@sub_admin)
    assert_match /already/i, flash[:alert]
  end

  test "PATCH demote is idempotent when user is already creator" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    patch demote_admin_user_path(@creator)
    assert_redirected_to admin_user_path(@creator)
    assert_match /already/i, flash[:alert]
  end
end
