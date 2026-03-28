require "test_helper"

class UserMailerVerifyEmailTest < ActionMailer::TestCase
  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "verify@example.com", name: "Verify User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL
    )
    @ev = @user.create_email_verification!(last_sent_at: Time.current)
  end

  test "verify_email sends to user email with correct subject" do
    mail = UserMailer.verify_email(@ev)
    assert_equal [@user.email], mail.to
    assert_equal "Verify your Forum email address", mail.subject
  end

  test "verify_email body contains token link" do
    mail = UserMailer.verify_email(@ev)
    assert_includes mail.body.encoded, @ev.token
  end
end
