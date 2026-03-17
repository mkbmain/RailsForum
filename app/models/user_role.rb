class UserRole < ApplicationRecord
  self.record_timestamps = false  # table has created_at only, no updated_at

  belongs_to :user
  belongs_to :role
end
