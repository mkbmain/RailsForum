class Category < ApplicationRecord
  has_many :posts

  default_scope { order(:position) }

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
end
