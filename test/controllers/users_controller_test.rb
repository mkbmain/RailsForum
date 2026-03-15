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
end
