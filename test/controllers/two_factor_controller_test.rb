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

  # ─── login flow with 2FA ─────────────────────────────────────────────────────

  test "login redirects to verify page when user has 2FA enabled" do
    secret = ROTP::Base32.random
    @user.update!(totp_secret: secret)

    delete logout_path
    post login_path, params: { email: @user.email, password: "password123" }

    assert_redirected_to verify_two_factor_path
    assert_nil session[:user_id]
    assert_equal @user.id, session[:awaiting_2fa]
  end

  test "POST /two_factor/verify with valid TOTP code completes login" do
    secret = ROTP::Base32.random
    @user.update!(totp_secret: secret)
    delete logout_path
    post login_path, params: { email: @user.email, password: "password123" }

    valid_code = ROTP::TOTP.new(secret).now
    post verify_two_factor_path, params: { code: valid_code }

    assert_redirected_to root_path
    assert_equal @user.id, session[:user_id]
    assert_nil session[:awaiting_2fa]
  end

  test "POST /two_factor/verify with invalid TOTP code increments throttle and re-renders" do
    secret = ROTP::Base32.random
    @user.update!(totp_secret: secret)
    delete logout_path
    post login_path, params: { email: @user.email, password: "password123" }

    post verify_two_factor_path, params: { code: "000000" }

    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "POST /two_factor/verify with valid backup code completes login and marks code used" do
    secret = ROTP::Base32.random
    @user.update!(totp_secret: secret)
    delete logout_path
    plaintext = BackupCode.generate_for(@user)
    post login_path, params: { email: @user.email, password: "password123" }

    post verify_two_factor_path, params: { code: plaintext.first }

    assert_redirected_to root_path
    assert_equal @user.id, session[:user_id]
    used = @user.backup_codes.find { |bc| BCrypt::Password.new(bc.digest) == plaintext.first }
    assert_not_nil used&.used_at
  end

  test "POST /two_factor/verify with already-used backup code is rejected" do
    secret = ROTP::Base32.random
    @user.update!(totp_secret: secret)
    delete logout_path
    plaintext = BackupCode.generate_for(@user)
    post login_path, params: { email: @user.email, password: "password123" }
    post verify_two_factor_path, params: { code: plaintext.first }

    delete logout_path
    post login_path, params: { email: @user.email, password: "password123" }
    post verify_two_factor_path, params: { code: plaintext.first }

    assert_response :unprocessable_entity
  end

  test "POST /two_factor/verify when throttled returns 429" do
    secret = ROTP::Base32.random
    @user.update!(totp_secret: secret)
    delete logout_path
    post login_path, params: { email: @user.email, password: "password123" }

    5.times { post verify_two_factor_path, params: { code: "000000" } }
    post verify_two_factor_path, params: { code: "000000" }

    assert_response :too_many_requests
  end

  # ─── disable 2FA ────────────────────────────────────────────────────────────

  test "DELETE /two_factor with correct password disables 2FA and destroys backup codes" do
    secret = ROTP::Base32.random
    @user.update!(totp_secret: secret)
    BackupCode.generate_for(@user)

    delete two_factor_path, params: { current_password: "password123" }

    assert_redirected_to edit_user_path(@user)
    assert flash[:notice].present?
    @user.reload
    assert_not @user.totp_enabled?
    assert_equal 0, @user.backup_codes.count
  end

  test "DELETE /two_factor with wrong password redirects with alert and leaves 2FA enabled" do
    secret = ROTP::Base32.random
    @user.update!(totp_secret: secret)

    delete two_factor_path, params: { current_password: "wrongpassword" }

    assert_redirected_to edit_user_path(@user)
    assert flash[:alert].present?
    assert @user.reload.totp_enabled?
  end

  # ─── regenerate backup codes ─────────────────────────────────────────────────

  test "POST /two_factor/backup_codes with correct password replaces backup codes" do
    secret = ROTP::Base32.random
    @user.update!(totp_secret: secret)
    BackupCode.generate_for(@user)
    old_digests = @user.backup_codes.pluck(:digest)

    post backup_codes_two_factor_path, params: { current_password: "password123" }

    assert_response :success
    assert_template :backup_codes
    @user.reload
    assert_equal 8, @user.backup_codes.count
    assert_not_equal old_digests.sort, @user.backup_codes.pluck(:digest).sort
  end

  test "POST /two_factor/backup_codes with wrong password redirects with alert" do
    secret = ROTP::Base32.random
    @user.update!(totp_secret: secret)
    BackupCode.generate_for(@user)

    post backup_codes_two_factor_path, params: { current_password: "wrongpassword" }

    assert_redirected_to edit_user_path(@user)
    assert flash[:alert].present?
  end
end
