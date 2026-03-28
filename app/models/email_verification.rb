class EmailVerification < ApplicationRecord
  belongs_to :user
  has_secure_token :token

  EXPIRY          = 24.hours
  RESEND_COOLDOWN = 3.minutes

  def expired?
    created_at < EXPIRY.ago
  end

  def on_cooldown?
    last_sent_at && last_sent_at >= RESEND_COOLDOWN.ago
  end
end
