class Club < ApplicationRecord
  belongs_to :created_by, class_name: "User"
  has_many :club_memberships
  has_many :members, through: :club_memberships, source: :user
end
