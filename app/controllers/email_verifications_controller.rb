class EmailVerificationsController < ApplicationController
  before_action :require_login, only: [ :resend ]

  def show
    ev = EmailVerification.find_by(token: params[:token])

    if ev.nil? || ev.expired?
      redirect_to root_path, alert: "That verification link is invalid or has expired."
      return
    end

    ev.user.update_column(:email_verified_at, Time.current)
    ev.destroy
    redirect_to root_path, notice: "Email verified. Thank you!"
  end

  def resend
    return if current_user.email_verified_at.present?

    ev = current_user.email_verification

    if ev&.on_cooldown?
      redirect_to root_path, notice: "Verification email already sent. Please check your inbox."
      return
    end

    ev&.destroy
    ev = current_user.create_email_verification!(last_sent_at: Time.current)
    UserMailer.verify_email(ev).deliver_later
    redirect_to root_path, notice: "Verification email sent. Please check your inbox."
  end
end
