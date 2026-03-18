class UserBadge < ApplicationRecord
  belongs_to :user
  belongs_to :badge
  belongs_to :challenge, optional: true
end
