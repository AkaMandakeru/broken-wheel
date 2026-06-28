class SeasonObjective < ApplicationRecord
  belongs_to :season
  has_many :season_objective_completions, dependent: :destroy

  # Action-based season goals that aren't workout challenges.
  KINDS = %w[join_club club_workout].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :xp_reward, numericality: { greater_than_or_equal_to: 0 }
  validates :target, numericality: { greater_than: 0 }
end
