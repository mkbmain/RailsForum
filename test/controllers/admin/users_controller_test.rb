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
end
