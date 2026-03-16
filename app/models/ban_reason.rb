class BanReason < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
