class PasswordReset < ApplicationRecord
  belongs_to :user
  has_secure_token :token

  EXPIRY          = 1.hour
  REUSE_THRESHOLD = 20.minutes
  RESEND_COOLDOWN = 3.minutes

  def expired?
    created_at < EXPIRY.ago
  end

  def reusable?
    created_at >= (EXPIRY - REUSE_THRESHOLD).ago
  end

  def on_cooldown?
    last_sent_at && last_sent_at >= RESEND_COOLDOWN.ago
  end
end
