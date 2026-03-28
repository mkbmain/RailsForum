require "test_helper"

class PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  # Rails 7.1+ includes ActionMailer::TestHelper in ActiveSupport::TestCase, so
  # assert_emails is available here. Include it explicitly for clarity and safety.
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    Provider.find_or_create_by!(id: Provider::GOOGLE,   name: "google")
    @user = User.create!(
      email: "reset@example.com", name: "Reset User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL
    )
    @oauth_user = User.create!(
      email: "oauth@example.com", name: "OAuth User",
      provider_id: Provider::GOOGLE, uid: "oauth-uid-123"
    )
  end

  teardown do
    Rails.cache.clear
  end

  # ─── new ────────────────────────────────────────────────────────────────────
  test "GET /password_resets/new renders the email form" do
    get new_password_reset_path
    assert_response :success
    assert_select "form"
  end

  # ─── create: no information leak ────────────────────────────────────────────
  test "POST /password_resets with unknown email redirects with generic flash" do
    assert_emails 0 do
      post password_resets_path, params: { email: "nobody@example.com" }
    end
    assert_redirected_to login_path
    assert flash[:notice].present?
  end

  test "POST /password_resets with OAuth user email redirects with generic flash, no row created" do
    assert_emails 0 do
      post password_resets_path, params: { email: @oauth_user.email }
    end
    assert_redirected_to login_path
    assert_nil @oauth_user.reload.password_reset
  end

  # ─── create: first valid request ────────────────────────────────────────────
  test "POST /password_resets creates reset row with last_sent_at set and enqueues email" do
    assert_emails 1 do
      post password_resets_path, params: { email: @user.email }
    end
    assert_redirected_to login_path
    @user.reload
    assert_not_nil @user.password_reset
    assert_not_nil @user.password_reset.last_sent_at
  end

  # ─── create: cooldown on brand-new token ────────────────────────────────────
  test "second POST within 3-minute cooldown suppresses email" do
    assert_emails 1 do
      post password_resets_path, params: { email: @user.email }
    end
    assert_emails 0 do
      post password_resets_path, params: { email: @user.email }
    end
    assert_redirected_to login_path
  end

  # ─── create: resend when reusable and outside cooldown ──────────────────────
  test "POST when token is reusable and outside cooldown updates last_sent_at and resends" do
    original_reset = travel_to(10.minutes.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    original_reset.update_column(:last_sent_at, 5.minutes.ago)
    original_token = original_reset.token

    assert_emails 1 do
      post password_resets_path, params: { email: @user.email }
    end

    @user.password_reset.reload
    assert_equal original_token, @user.password_reset.token
    assert @user.password_reset.last_sent_at >= 1.minute.ago
  end

  # ─── create: token in 41–59 min zone (not reusable, not expired) ────────────
  test "POST when token is 45 minutes old destroys old row and creates new token" do
    old_reset = travel_to(45.minutes.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    old_token = old_reset.token

    assert_emails 1 do
      post password_resets_path, params: { email: @user.email }
    end

    @user.reload
    assert_not_nil @user.password_reset
    assert_not_equal old_token, @user.password_reset.token
  end

  # ─── create: expired token ──────────────────────────────────────────────────
  test "POST when token is expired destroys old row and creates new token" do
    old_reset = travel_to(2.hours.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    old_token = old_reset.token

    assert_emails 1 do
      post password_resets_path, params: { email: @user.email }
    end

    @user.reload
    assert_not_nil @user.password_reset
    assert_not_equal old_token, @user.password_reset.token
  end

  # ─── edit ───────────────────────────────────────────────────────────────────
  test "GET /password_resets/:token/edit with unknown token redirects with alert" do
    get edit_password_reset_path("nonexistent-token")
    assert_redirected_to new_password_reset_path
    assert flash[:alert].present?
  end

  test "GET /password_resets/:token/edit with expired token redirects with alert" do
    reset = travel_to(2.hours.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    get edit_password_reset_path(reset.token)
    assert_redirected_to new_password_reset_path
    assert flash[:alert].present?
  end

  test "GET /password_resets/:token/edit with valid token renders the form" do
    reset = @user.create_password_reset!(last_sent_at: Time.current)
    get edit_password_reset_path(reset.token)
    assert_response :success
    assert_select "form"
  end

  test "GET /password_resets/:token/edit with OAuth user token redirects to login" do
    # Defensive guard: crafted URL for a token belonging to an OAuth user
    # should redirect rather than render the form.
    # In normal flow create never issues a token for OAuth users; this guards
    # against crafted URLs or future code changes.
    reset = PasswordReset.create!(user: @oauth_user, last_sent_at: Time.current)
    get edit_password_reset_path(reset.token)
    assert_redirected_to login_path
    assert flash[:alert].present?
  end

  test "PATCH /password_resets/:token with OAuth user token redirects to login" do
    reset = PasswordReset.create!(user: @oauth_user, last_sent_at: Time.current)
    patch password_reset_path(reset.token),
          params: { user: { password: "newpass123", password_confirmation: "newpass123" } }
    assert_redirected_to login_path
    assert flash[:alert].present?
  end

  # ─── update ─────────────────────────────────────────────────────────────────
  test "PATCH with expired token redirects" do
    reset = travel_to(2.hours.ago) { @user.create_password_reset!(last_sent_at: Time.current) }
    patch password_reset_path(reset.token),
          params: { user: { password: "newpass123", password_confirmation: "newpass123" } }
    assert_redirected_to new_password_reset_path
  end

  test "PATCH happy path updates password, destroys reset row, and logs user in" do
    reset = @user.create_password_reset!(last_sent_at: Time.current)
    patch password_reset_path(reset.token),
          params: { user: { password: "newpass123", password_confirmation: "newpass123" } }
    assert_redirected_to root_path
    assert flash[:notice].present?
    assert_equal @user.id, session[:user_id]
    assert_nil PasswordReset.find_by(id: reset.id)
    assert @user.reload.authenticate("newpass123")
  end

  test "PATCH with mismatched passwords re-renders edit with 422" do
    reset = @user.create_password_reset!(last_sent_at: Time.current)
    patch password_reset_path(reset.token),
          params: { user: { password: "newpass123", password_confirmation: "wrongpass" } }
    assert_response :unprocessable_entity
    assert_not_nil PasswordReset.find_by(id: reset.id)
  end

  test "PATCH with blank password re-renders edit with 422" do
    reset = @user.create_password_reset!(last_sent_at: Time.current)
    patch password_reset_path(reset.token),
          params: { user: { password: "", password_confirmation: "" } }
    assert_response :unprocessable_entity
  end

  test "PATCH with password shorter than 6 characters re-renders with 422" do
    reset = @user.create_password_reset!(last_sent_at: Time.current)
    patch password_reset_path(reset.token),
          params: { user: { password: "abc", password_confirmation: "abc" } }
    assert_response :unprocessable_entity
  end

  test "PATCH with blank confirmation and present password re-renders with 422" do
    reset = @user.create_password_reset!(last_sent_at: Time.current)
    patch password_reset_path(reset.token),
          params: { user: { password: "newpass123", password_confirmation: "" } }
    assert_response :unprocessable_entity
  end
end
