class SeasonActivity < ApplicationRecord
  belongs_to :season
  belongs_to :user

  KINDS = %w[challenge_completed level_up reward_unlocked].freeze

  scope :recent, -> { order(created_at: :desc) }
end
