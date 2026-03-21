require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
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
  end

  test "GET /admin redirects guest to login" do
    get admin_root_path
    assert_redirected_to login_path
  end

  test "GET /admin redirects creator to root" do
    post login_path, params: { email: "creator@example.com", password: "pass123" }
    get admin_root_path
    assert_redirected_to root_path
  end

  test "GET /admin is accessible to sub_admin" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    get admin_root_path
    assert_response :success
  end

  test "GET /admin is accessible to admin" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_root_path
    assert_response :success
  end

  test "GET /admin shows stat counts including removed posts" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    category = Category.find_or_create_by!(id: 2, name: "General")
    @creator.posts.create!(title: "Visible Post", body: "body text here ok", category: category)
    removed = @creator.posts.create!(title: "Removed Post", body: "body text here ok", category: category)
    removed.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
    get admin_root_path
    assert_response :success
    assert_match "2", response.body
  end

  test "GET /admin shows activity feed with ban and removed post" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    BanReason.find_or_create_by!(name: "Spam")
    ban_reason = BanReason.find_by!(name: "Spam")
    UserBan.create!(user: @creator, ban_reason: ban_reason, banned_by: @admin,
                    banned_from: Time.current, banned_until: 2.hours.from_now)
    category = Category.find_or_create_by!(id: 2, name: "General")
    p = @creator.posts.create!(title: "Doomed Post", body: "body text here ok", category: category)
    p.update_columns(removed_at: Time.current, removed_by_id: @admin.id)
    get admin_root_path
    assert_response :success
    assert_match "Spam", response.body
    assert_match "Doomed Post", response.body
  end
end
