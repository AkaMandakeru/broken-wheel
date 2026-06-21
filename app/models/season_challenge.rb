class SeasonChallenge < ApplicationRecord
  belongs_to :season
  belongs_to :challenge
  has_many :season_challenge_completions, dependent: :destroy

  validates :challenge_id, uniqueness: { scope: :season_id }
  validates :xp_reward, numericality: { greater_than_or_equal_to: 0 }
end
