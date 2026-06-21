class SeasonRewardGrant < ApplicationRecord
  belongs_to :season_participation
  belongs_to :season_reward

  validates :season_reward_id, uniqueness: { scope: :season_participation_id }
end
