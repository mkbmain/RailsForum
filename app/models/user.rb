class User < ApplicationRecord
  belongs_to :provider
  has_many :posts, dependent: :destroy
  has_many :replies, dependent: :destroy
  has_many :reactions, dependent: :destroy
  has_many :flags, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :sent_notifications, class_name: "Notification", foreign_key: :actor_id, dependent: :destroy
  has_many :user_bans
  has_many :user_roles
  has_many :roles, through: :user_roles
  has_one :password_reset, dependent: :destroy

  before_save { self.email = email&.downcase&.strip }
  before_validation :sanitize_name
  after_create :assign_creator_role

  has_secure_password validations: false

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  validates :avatar_url, format: { with: /\Ahttps:\/\/.*\z/i, message: "must be an https URL" },
                         allow_blank: true
  validates :password, presence: true, if: -> { internal? && new_record? }
  validates :password, length: { minimum: 6, allow_nil: true }, if: :internal?
  validates :password_confirmation, presence: true, if: -> { internal? && new_record? }
  validate :password_matches_confirmation, if: -> { internal? && password.present? && password_confirmation.present? }

  def self.from_omniauth(auth, provider_id)
    raise ArgumentError, "OAuth response missing email" unless auth.info.email.present?
    find_or_initialize_by(uid: auth.uid, provider_id: provider_id).tap do |user|
      if user.new_record?
        user.email = auth.info.email
        user.name  = auth.info.name
      end
      user.avatar_url = auth.info.image
      user.save!
    end
  end

  def internal?
    provider_id == Provider::INTERNAL
  end

  def has_role?(name)
    roles.exists?(name: name)
  end

  def creator?   = has_role?(Role::CREATOR)
  def sub_admin? = has_role?(Role::SUB_ADMIN)
  def admin?     = has_role?(Role::ADMIN)
  def moderator? = sub_admin? || admin?

  def mention_handle
    name.gsub(" ", "_").gsub(/[^\w]/, "").downcase
  end

  def self.find_by_mention_handle(handle)
    normalized = handle.downcase.gsub("_", " ")
    find_by(
      "LOWER(REGEXP_REPLACE(name, '[^a-zA-Z0-9 ]', '', 'g')) = LOWER(REGEXP_REPLACE(?, '[^a-zA-Z0-9 ]', '', 'g'))",
      normalized
    )
  end

  private

  def sanitize_name
    self.name = name.gsub("_", " ") if name.present?
  end

  def assign_creator_role
    roles << Role.find_by!(name: Role::CREATOR)
  end

  def password_matches_confirmation
    errors.add(:password_confirmation, "doesn't match Password") unless password == password_confirmation
  end
end
