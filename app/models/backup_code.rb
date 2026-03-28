class BackupCode < ApplicationRecord
  belongs_to :user

  scope :unused, -> { where(used_at: nil) }

  def self.generate_for(user)
    plaintext_codes = Array.new(8) { SecureRandom.alphanumeric(10) }
    plaintext_codes.each do |code|
      user.backup_codes.create!(digest: BCrypt::Password.create(code))
    end
    plaintext_codes
  end

  def self.consume_for(user, submitted_code)
    user.backup_codes.unused.find_each do |backup_code|
      next unless BCrypt::Password.new(backup_code.digest) == submitted_code

      BackupCode.transaction do
        locked = BackupCode.lock.find(backup_code.id)
        return false if locked.used_at.present?

        locked.update!(used_at: Time.current)
      end
      return true
    end
    false
  end
end
