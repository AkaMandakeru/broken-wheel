class SeasonChallengeCompletion < ApplicationRecord
  belongs_to :season_participation
  belongs_to :season_challenge

  validates :season_challenge_id, uniqueness: { scope: :season_participation_id }
end
