class SeasonReward < ApplicationRecord
  belongs_to :season
  has_many :season_reward_grants, dependent: :destroy

  REWARD_TYPES = %w[title badge theme].freeze

  validates :reward_type, inclusion: { in: REWARD_TYPES }
  validates :reward_key, presence: true
  validates :level, numericality: { greater_than: 0 }
end
