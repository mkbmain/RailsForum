class UserMailer < ApplicationMailer
  def password_reset(reset)
    @reset = reset
    @user = reset.user
    mail to: @user.email, subject: "Reset your Forum password"
  end

  def verify_email(verification)
    @verification = verification
    @user = verification.user
    mail to: @user.email, subject: "Verify your Forum email address"
  end
end
