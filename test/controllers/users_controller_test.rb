require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
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
end
