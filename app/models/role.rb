class Role < ApplicationRecord
  CREATOR   = "creator"
  SUB_ADMIN = "sub_admin"
  ADMIN     = "admin"

  has_many :user_roles
  has_many :users, through: :user_roles

  validates :name, presence: true, uniqueness: true
end
