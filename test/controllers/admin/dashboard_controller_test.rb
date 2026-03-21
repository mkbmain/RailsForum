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
end
