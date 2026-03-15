class Post < ApplicationRecord
  belongs_to :user
  belongs_to :category

  has_many :replies, dependent: :destroy

  attribute :category_id, :integer, default: 1

  validates :title, presence: true, length: { maximum: 200 }
  validates :body, presence: true, length: { maximum: 1000 }

  def last_activity_at
    last_replied_at || created_at
  end
end
