module VerifiedEmail
  extend ActiveSupport::Concern

  private

  def require_verified_email
    return if current_user.email_verified_at.present?
    flash[:alert] = "Please verify your email address before posting. Check your inbox or resend below."
    redirect_to root_path
  end
end
