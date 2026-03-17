class Post < ApplicationRecord
  belongs_to :user
  belongs_to :category
  belongs_to :removed_by, class_name: "User", optional: true

  has_many :replies, dependent: :destroy

  scope :visible, -> { where(removed_at: nil) }

  attribute :category_id, :integer, default: 1

  validates :title, presence: true, length: { maximum: 200 }
  validates :body, presence: true, length: { maximum: 1000 }

  after_create_commit { update_column(:last_edited_at, created_at) }

  def last_activity_at
    last_replied_at || created_at
  end

  def edited?
    last_edited_at != created_at
  end

  def removed? = removed_at.present?
end
