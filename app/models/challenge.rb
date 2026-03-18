class Challenge < ApplicationRecord
  has_many :challenge_participations
  has_many :participants, through: :challenge_participations, source: :user
  has_many :timeline_posts
end
