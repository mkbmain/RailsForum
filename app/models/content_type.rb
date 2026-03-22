class ContentType < ApplicationRecord
  self.primary_key = :id

  CONTENT_POST  = 1
  CONTENT_REPLY = 2
end
