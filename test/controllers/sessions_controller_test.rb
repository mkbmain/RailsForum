require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(email: "user@example.com", name: "Test User",
                         password: "password123", password_confirmation: "password123", provider_id: 3)
  end

  teardown do
    Rails.cache.clear
  end

  test "GET /login shows login form" do
    get login_path
    assert_response :success
    assert_select "form"
  end

  test "POST /login with valid credentials sets session" do
    post login_path, params: { email: "user@example.com", password: "password123" }
    assert_redirected_to root_path
    assert_equal @user.id, session[:user_id]
  end

  test "POST /login with bad password shows error" do
    post login_path, params: { email: "user@example.com", password: "wrong" }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "DELETE /logout clears session" do
    post login_path, params: { email: "user@example.com", password: "password123" }
    delete logout_path
    assert_redirected_to root_path
    assert_nil session[:user_id]
  end

  test "POST /login is blocked after too many failed attempts" do
    LoginThrottle::MAX_ATTEMPTS.times do
      post login_path, params: { email: "user@example.com", password: "wrong" }
    end
    post login_path, params: { email: "user@example.com", password: "wrong" }
    assert_response :too_many_requests
    assert_select "form"  # login form still shown
  end

  test "POST /login throttle clears on successful login" do
    (LoginThrottle::MAX_ATTEMPTS - 1).times do
      post login_path, params: { email: "user@example.com", password: "wrong" }
    end
    post login_path, params: { email: "user@example.com", password: "password123" }
    assert_redirected_to root_path

    # After successful login, a wrong attempt should NOT be immediately blocked
    delete logout_path
    post login_path, params: { email: "user@example.com", password: "wrong" }
    assert_response :unprocessable_entity  # not :too_many_requests
  end

  test "awaiting_2fa session is timed out after SESSION_TIMEOUT_MINUTES" do
    skip if SESSION_TIMEOUT_MINUTES == 0

    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    user = User.create!(
      email: "sess@example.com", name: "Sess User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL,
      email_verified_at: Time.current
    )
    secret = ROTP::Base32.random
    user.update!(totp_secret: secret)

    post login_path, params: { email: user.email, password: "password123" }
    assert_equal user.id, session[:awaiting_2fa]

    travel (SESSION_TIMEOUT_MINUTES + 1).minutes do
      get verify_two_factor_path
      assert_redirected_to login_path
      assert flash[:alert].present?
      assert_nil session[:awaiting_2fa]
    end
  end

  test "awaiting_2fa session touch_session updates last_active_at" do
    skip if SESSION_TIMEOUT_MINUTES == 0

    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    user = User.create!(
      email: "sess2@example.com", name: "Sess User 2",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL,
      email_verified_at: Time.current
    )
    secret = ROTP::Base32.random
    user.update!(totp_secret: secret)

    post login_path, params: { email: user.email, password: "password123" }
    assert_not_nil session[:last_active_at]
  end
end
