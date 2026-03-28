require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    Provider.find_or_create_by!(id: Provider::GOOGLE,   name: "google")
  end

  test "GET /signup shows form" do
    get signup_path
    assert_response :success
  end

  test "POST /signup with valid data creates user and logs in" do
    assert_difference "User.count", 1 do
      post signup_path, params: {
        user: { email: "new@example.com", name: "New User",
                password: "password123", password_confirmation: "password123" }
      }
    end
    assert_redirected_to root_path
    assert_not_nil session[:user_id]
  end

  test "POST /signup with invalid data re-renders form" do
    post signup_path, params: {
      user: { email: "", name: "", password: "short", password_confirmation: "short" }
    }
    assert_response :unprocessable_entity
    assert_equal 0, User.count
  end

  test "GET /users/:id shows public profile" do
    user = User.create!(email: "profile@example.com", name: "Profile User",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    get user_path(user)
    assert_response :success
    assert_select "h1", text: /Profile User/
  end

  test "GET /users/:id shows profile without login" do
    user = User.create!(email: "pub@example.com", name: "Public User",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    get user_path(user)
    assert_response :success
  end

  test "GET /users/:id/edit requires login" do
    user = User.create!(email: "edit@example.com", name: "Edit User",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    get edit_user_path(user)
    assert_redirected_to login_path
  end

  test "GET /users/:id/edit is forbidden for other users" do
    owner = User.create!(email: "owner@example.com", name: "Owner",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    other = User.create!(email: "intruder@example.com", name: "Intruder",
                         password: "pass123", password_confirmation: "pass123",
                         provider_id: 3)
    post login_path, params: { email: "intruder@example.com", password: "pass123" }
    get edit_user_path(owner)
    assert_redirected_to root_path
  end

  test "PATCH /users/:id updates name and bio" do
    user = User.create!(email: "patch@example.com", name: "Old Name",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    post login_path, params: { email: "patch@example.com", password: "pass123" }
    patch user_path(user), params: { user: { name: "New Name", bio: "Hello!" } }
    assert_redirected_to user_path(user)
    assert_equal "New Name", user.reload.name
    assert_equal "Hello!",   user.reload.bio
  end

  test "PATCH /users/:id changes password with correct current password" do
    user = User.create!(email: "pwchange@example.com", name: "PW User",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    post login_path, params: { email: "pwchange@example.com", password: "pass123" }
    patch user_path(user), params: { user: { name: "PW User", current_password: "pass123",
                                              password: "newpass456", password_confirmation: "newpass456" } }
    assert_redirected_to user_path(user)
    assert user.reload.authenticate("newpass456")
  end

  test "PATCH /users/:id rejects wrong current password" do
    user = User.create!(email: "badpw@example.com", name: "Bad PW",
                        password: "pass123", password_confirmation: "pass123",
                        provider_id: 3)
    post login_path, params: { email: "badpw@example.com", password: "pass123" }
    patch user_path(user), params: { user: { name: "Bad PW", current_password: "WRONG",
                                              password: "newpass456", password_confirmation: "newpass456" } }
    assert_response :unprocessable_entity
    assert user.reload.authenticate("pass123"), "Password should not have changed"
  end

  # ---- Activity pagination tests ----

  def create_active_user(email:, name:)
    User.create!(email: email, name: name,
                 password: "pass123", password_confirmation: "pass123",
                 provider_id: 3)
  end

  test "GET /users/:id page 1 shows 20 items and has_more link when 22 total" do
    user     = create_active_user(email: "pg1@example.com", name: "Pg1User")
    category = categories(:other)

    # 12 posts + 10 replies = 22 items; page 1 should show 20
    posts = (1..12).map { |i| Post.create!(title: "Post #{i}", body: "body", user: user, category: category, created_at: i.days.ago) }
    (1..10).map { |i| Reply.create!(body: "reply #{i}", user: user, post: posts.first, created_at: (i + 0.5).days.ago) }

    get user_path(user)
    assert_response :success

    post_badges  = css_select("span").select { |n| n.text.strip == "Post" }.size
    reply_badges = css_select("span").select { |n| n.text.strip == "Reply" }.size
    assert_equal 20, post_badges + reply_badges, "expected 20 activity items on page 1"
    assert_select "a", text: "Older →", count: 1
  end

  test "GET /users/:id page 2 shows remaining 2 items and no has_more link" do
    user     = create_active_user(email: "pg2@example.com", name: "Pg2User")
    category = categories(:other)

    posts = (1..12).map { |i| Post.create!(title: "Post #{i}", body: "body", user: user, category: category, created_at: i.days.ago) }
    (1..10).map { |i| Reply.create!(body: "reply #{i}", user: user, post: posts.first, created_at: (i + 0.5).days.ago) }

    get user_path(user, page: 2)
    assert_response :success

    post_badges  = css_select("span").select { |n| n.text.strip == "Post" }.size
    reply_badges = css_select("span").select { |n| n.text.strip == "Reply" }.size
    assert_equal 2, post_badges + reply_badges, "expected 2 activity items on page 2"
    assert_select "a", text: "Older →", count: 0
  end

  test "GET /users/:id activity excludes removed posts" do
    user     = create_active_user(email: "vis@example.com", name: "VisUser")
    category = categories(:other)

    Post.create!(title: "VisiblePost", body: "body", user: user, category: category)
    Post.create!(title: "RemovedPost", body: "body", user: user, category: category, removed_at: 1.hour.ago)

    get user_path(user)
    assert_response :success
    assert_select "a", text: "VisiblePost"
    assert_select "a", text: "RemovedPost", count: 0
  end

  test "POST /signup sends verification email and leaves email_verified_at nil" do
    assert_emails 1 do
      post signup_path, params: {
        user: {
          email: "newuser@example.com", name: "New User",
          password: "password123", password_confirmation: "password123"
        }
      }
    end
    user = User.find_by!(email: "newuser@example.com")
    assert_nil user.email_verified_at
    assert_not_nil user.email_verification
  end
end
