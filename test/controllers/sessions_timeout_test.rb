# test/controllers/sessions_timeout_test.rb
require "test_helper"

class SessionsTimeoutTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: 3, name: "internal")
    @user = User.create!(
      email: "timeout@example.com",
      name: "Timeout User",
      password: "password123",
      password_confirmation: "password123",
      provider_id: 3
    )
    # Use a short timeout (1 min) for all tests so travel_to distances are small
    @original_timeout = SESSION_TIMEOUT_MINUTES
    silence_warnings { Object.const_set(:SESSION_TIMEOUT_MINUTES, 1) }
  end

  teardown do
    silence_warnings { Object.const_set(:SESSION_TIMEOUT_MINUTES, @original_timeout) }
  end

  # Helper: log in as @user at the current time (touch_session writes last_active_at)
  def login_user
    post login_path, params: { email: "timeout@example.com", password: "password123" }
  end

  # -------------------------------------------------------------------------
  # Expired session — HTML request
  # -------------------------------------------------------------------------
  test "expired session redirects to login with alert for HTML requests" do
    # Log in 2 minutes ago — last_active_at is set to that time
    travel_to 2.minutes.ago do
      login_user
    end

    # Now (back at current time) make an HTML request — timeout check fires
    get root_path
    assert_redirected_to login_path
    assert_equal "Your session has expired. Please log in again.", flash[:alert]
    assert_nil session[:user_id]
  end

  # -------------------------------------------------------------------------
  # Expired session — Turbo Frame request
  # -------------------------------------------------------------------------
  test "expired session returns 401 for Turbo Frame requests" do
    travel_to 2.minutes.ago do
      login_user
    end

    get root_path, headers: { "Turbo-Frame" => "main" }
    assert_response :unauthorized
    assert_nil session[:user_id]
  end

  # -------------------------------------------------------------------------
  # Expired session — Turbo Stream request
  # -------------------------------------------------------------------------
  test "expired session returns 401 for Turbo Stream requests" do
    travel_to 2.minutes.ago do
      login_user
    end

    get root_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :unauthorized
    assert_nil session[:user_id]
  end

  # -------------------------------------------------------------------------
  # Active session — within timeout window
  # -------------------------------------------------------------------------
  test "active session within timeout window stays logged in and refreshes timestamp" do
    travel_to 30.seconds.ago do
      login_user
    end

    before_ts = session[:last_active_at]
    get root_path
    assert_response :success
    assert_equal @user.id, session[:user_id]
    # touch_session should have updated the timestamp
    assert session[:last_active_at] >= before_ts
  end

  # -------------------------------------------------------------------------
  # At exact boundary — not expired (strictly greater than)
  # -------------------------------------------------------------------------
  test "session at exact timeout boundary is not expired" do
    travel_to 1.minute.ago do
      login_user
    end

    get root_path
    assert_response :success
    assert_equal @user.id, session[:user_id]
  end

  # -------------------------------------------------------------------------
  # Absent last_active_at — treated as active (deploy transition)
  # -------------------------------------------------------------------------
  test "absent last_active_at is treated as active and gets written" do
    # Log in with timeout disabled so touch_session doesn't write last_active_at
    silence_warnings { Object.const_set(:SESSION_TIMEOUT_MINUTES, 0) }
    login_user
    assert_nil session[:last_active_at], "last_active_at should not be written when timeout is disabled"

    # Re-enable timeout — simulates a deploy that activates the feature
    silence_warnings { Object.const_set(:SESSION_TIMEOUT_MINUTES, 1) }

    # Make a request — check_session_timeout sees absent last_active_at, writes it, does NOT expire
    get root_path
    assert_response :success
    assert_equal @user.id, session[:user_id]
    assert_not_nil session[:last_active_at], "last_active_at should be written on first request after feature activation"
  end

  # -------------------------------------------------------------------------
  # Timeout disabled — SESSION_TIMEOUT_MINUTES = 0
  # -------------------------------------------------------------------------
  test "timeout disabled: old session is not expired and last_active_at is not written" do
    silence_warnings { Object.const_set(:SESSION_TIMEOUT_MINUTES, 0) }

    travel_to 999.minutes.ago do
      login_user
    end

    get root_path
    assert_response :success
    assert_equal @user.id, session[:user_id]
    # last_active_at should NOT be written when timeout is disabled
    assert_nil session[:last_active_at]
  end

  # -------------------------------------------------------------------------
  # Unauthenticated request — no session, no-op
  # -------------------------------------------------------------------------
  test "unauthenticated request is unaffected by timeout logic" do
    get root_path
    assert_response :success
    assert_nil session[:user_id]
    assert_nil session[:last_active_at]
  end
end
