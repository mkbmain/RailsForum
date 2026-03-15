class User < ApplicationRecord
  belongs_to :provider
  has_many :posts, dependent: :destroy
  has_many :replies, dependent: :destroy

  has_secure_password validations: false

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  validates :avatar_url, format: { with: /\Ahttps:\/\//i, message: "must be an https URL" },
                         allow_blank: true
  validates :password, presence: true, if: -> { internal? && new_record? }
  validates :password, length: { minimum: 6, allow_nil: true }, if: :internal?
  validates :password_confirmation, presence: true, if: -> { internal? && new_record? }
  validate :password_matches_confirmation, if: -> { internal? && password.present? && password_confirmation.present? }

  def self.from_omniauth(auth, provider_id)
    raise ArgumentError, "OAuth response missing email" unless auth.info.email.present?
    find_or_initialize_by(uid: auth.uid, provider_id: provider_id).tap do |user|
      user.email       = auth.info.email
      user.name        = auth.info.name
      user.avatar_url  = auth.info.image
      user.save!
    end
  end

  def internal?
    provider_id == Provider::INTERNAL
  end

  private

  def password_matches_confirmation
    errors.add(:password_confirmation, "doesn't match Password") unless password == password_confirmation
  end
end
