class Challenge < ApplicationRecord
  has_many :challenge_participations
  has_many :participants, through: :challenge_participations, source: :user
  has_many :timeline_posts

  def self.current_week_window(today: Date.current)
    today.beginning_of_week(:monday)..today.end_of_week(:monday)
  end
end
