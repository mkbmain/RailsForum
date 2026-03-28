require "test_helper"

class TwoFactorControllerTest < ActionDispatch::IntegrationTest
  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "2fa@example.com", name: "2FA User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL,
      email_verified_at: Time.current
    )
    post login_path, params: { email: @user.email, password: "password123" }
  end

  teardown { Rails.cache.clear }

  # ─── setup ──────────────────────────────────────────────────────────────────

  test "GET /two_factor/setup renders QR code page" do
    get setup_two_factor_path
    assert_response :success
    assert_select "form"
  end

  test "POST /two_factor/setup with invalid code re-renders setup with error" do
    get setup_two_factor_path  # seeds session[:pending_totp_secret]
    post setup_two_factor_path, params: { code: "000000" }
    assert_response :unprocessable_entity
  end

  test "POST /two_factor/setup with valid code saves totp_secret and renders backup codes" do
    get setup_two_factor_path
    secret = session[:pending_totp_secret]
    totp = ROTP::TOTP.new(secret)
    valid_code = totp.now

    post setup_two_factor_path, params: { code: valid_code }

    assert_response :success
    assert_template :backup_codes
    @user.reload
    assert @user.totp_enabled?
    assert_equal 8, @user.backup_codes.count
    assert_nil session[:pending_totp_secret]
  end

  test "GET /two_factor/setup requires login" do
    delete logout_path
    get setup_two_factor_path
    assert_redirected_to login_path
  end
end
