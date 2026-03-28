class UserMailer < ApplicationMailer
  def password_reset(reset)
    @reset = reset
    @user = reset.user
    mail to: @user.email, subject: "Reset your Forum password"
  end
end
