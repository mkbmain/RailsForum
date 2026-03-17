class UserBan < ApplicationRecord
  belongs_to :user
  belongs_to :ban_reason
  belongs_to :banned_by, class_name: "User", optional: true

  before_validation { self.banned_from ||= Time.current }

  validates :banned_from, :banned_until, presence: true
  validate :banned_until_after_banned_from

  private

  def banned_until_after_banned_from
    return unless banned_from.present? && banned_until.present?
    errors.add(:banned_until, "must be after banned from") if banned_until <= banned_from
  end
end
