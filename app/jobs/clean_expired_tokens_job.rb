class CleanExpiredTokensJob < ApplicationJob
  queue_as :background

  def perform
    PasswordReset.where("created_at < ?", PasswordReset::EXPIRY.ago).delete_all
    EmailVerification.where("created_at < ?", EmailVerification::EXPIRY.ago).delete_all
  end
end
