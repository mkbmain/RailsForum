require "test_helper"

class Admin::FlagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "u@example.com", name: "User",
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
    @post  = Post.create!(user: @user, title: "Post", body: "Body")
    @flag  = Flag.create!(user: @user, content_type_id: ContentType::CONTENT_POST,
                          flaggable_id: @post.id, reason: :spam)
  end

  # --- index auth ---

  test "index is accessible to sub_admin" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    get admin_flags_path
    assert_response :success
  end

  test "index is accessible to admin" do
    post login_path, params: { email: "admin@example.com", password: "pass123" }
    get admin_flags_path
    assert_response :success
  end

  test "index redirects regular users" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    get admin_flags_path
    assert_redirected_to root_path
  end

  test "index redirects guests" do
    get admin_flags_path
    assert_redirected_to login_path
  end

  # --- dismiss ---

  test "dismiss sets resolved_at and resolved_by_id" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch dismiss_admin_flag_path(@flag)
    @flag.reload
    assert_not_nil @flag.resolved_at
    assert_equal @sub_admin.id, @flag.resolved_by_id
    assert_redirected_to admin_flags_path
    assert_equal "Flag dismissed.", flash[:notice]
  end

  test "dismiss on already-resolved flag returns Already resolved notice" do
    @flag.update!(resolved_at: Time.current, resolved_by: @admin)
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch dismiss_admin_flag_path(@flag)
    assert_redirected_to admin_flags_path
    assert_equal "Already resolved.", flash[:notice]
  end

  test "dismiss on missing flag returns Already resolved notice" do
    post login_path, params: { email: "sub@example.com", password: "pass123" }
    patch dismiss_admin_flag_path(id: 99999)
    assert_redirected_to admin_flags_path
    assert_equal "Already resolved.", flash[:notice]
  end

  test "dismiss is rejected for regular users" do
    post login_path, params: { email: "u@example.com", password: "pass123" }
    patch dismiss_admin_flag_path(@flag)
    assert_redirected_to root_path
    @flag.reload
    assert_nil @flag.resolved_at
  end
end
