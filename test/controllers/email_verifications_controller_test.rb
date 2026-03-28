require "test_helper"

class EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "ev@example.com", name: "EV User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL
    )
  end

  test "GET /email_verifications/:token verifies user and redirects to root" do
    ev = @user.create_email_verification!(last_sent_at: Time.current)
    get email_verification_path(ev.token)
    assert_redirected_to root_path
    assert flash[:notice].present?
    assert_not_nil @user.reload.email_verified_at
    assert_nil EmailVerification.find_by(id: ev.id)
  end

  test "GET /email_verifications/:token with unknown token redirects with alert" do
    get email_verification_path("nonexistent-token")
    assert_redirected_to root_path
    assert flash[:alert].present?
  end

  test "GET /email_verifications/:token with expired token redirects with alert" do
    ev = travel_to(25.hours.ago) { @user.create_email_verification!(last_sent_at: Time.current) }
    get email_verification_path(ev.token)
    assert_redirected_to root_path
    assert flash[:alert].present?
    assert_nil @user.reload.email_verified_at
  end

  test "GET /email_verifications/:token for already-verified user redirects benignly" do
    @user.update_column(:email_verified_at, Time.current)
    ev = @user.create_email_verification!(last_sent_at: Time.current)
    get email_verification_path(ev.token)
    assert_redirected_to root_path
    assert flash[:notice].present?
  end

  test "POST /email_verifications/resend when logged in creates token and sends email" do
    post login_path, params: { email: @user.email, password: "password123" }

    assert_emails 1 do
      post resend_email_verifications_path
    end
    assert_redirected_to root_path
    assert flash[:notice].present?
    assert_not_nil @user.reload.email_verification
  end

  test "POST /email_verifications/resend when on cooldown suppresses email" do
    post login_path, params: { email: @user.email, password: "password123" }
    @user.create_email_verification!(last_sent_at: 1.minute.ago)

    assert_emails 0 do
      post resend_email_verifications_path
    end
    assert_redirected_to root_path
  end

  test "POST /email_verifications/resend when not logged in redirects to login" do
    post resend_email_verifications_path
    assert_redirected_to login_path
  end
end
