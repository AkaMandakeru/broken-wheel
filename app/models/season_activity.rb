class SeasonActivity < ApplicationRecord
  belongs_to :season
  # Community milestones belong to the season as a whole, so they carry no user.
  belongs_to :user, optional: true

  KINDS = %w[
    challenge_completed objective_completed level_up reward_unlocked
    daily_completed secret_discovered legacy_mission_completed
    community_milestone community_tier_cleared season_finalized season_started
  ].freeze

  validates :kind, inclusion: { in: KINDS }

  scope :recent, -> { order(created_at: :desc) }
  scope :community, -> { where(user_id: nil) }

  def community?
    user_id.nil?
  end
end
