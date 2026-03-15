class Provider < ApplicationRecord
  self.primary_key = :id

  has_many :users

  INTERNAL = 3
  GOOGLE    = 1
  MICROSOFT = 2
end
