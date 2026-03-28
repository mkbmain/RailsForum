require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  include Rails.application.routes.url_helpers

  def default_url_options
    { host: "example.com" }
  end

  setup do
    Provider.find_or_create_by!(id: Provider::INTERNAL, name: "internal")
    @user = User.create!(
      email: "mailer@example.com", name: "Mailer User",
      password: "password123", password_confirmation: "password123",
      provider_id: Provider::INTERNAL
    )
    @reset = @user.create_password_reset!(last_sent_at: Time.current)
  end

  test "password_reset sends to correct recipient with correct subject" do
    email = UserMailer.password_reset(@reset)
    assert_emails 1 do
      email.deliver_now
    end
    assert_equal [ "mailer@example.com" ], email.to
    assert_equal "Reset your Forum password", email.subject
  end

  test "password_reset email body contains the reset URL with correct token" do
    email = UserMailer.password_reset(@reset)
    expected_url = edit_password_reset_url(@reset.token)
    assert_match expected_url, email.html_part.body.to_s
    assert_match expected_url, email.text_part.body.to_s
  end
end
