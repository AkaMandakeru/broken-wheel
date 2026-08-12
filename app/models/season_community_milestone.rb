# frozen_string_literal: true

class SeasonCommunityMilestone < ApplicationRecord
  belongs_to :season_community_goal
  belongs_to :season_reward, optional: true

  validates :percent, numericality: { greater_than: 0, less_than_or_equal_to: 100 },
                      uniqueness: { scope: [ :season_community_goal_id, :tier ] }
  validates :tier, numericality: { greater_than: 0 }

  scope :reached, -> { where.not(reached_at: nil) }
  scope :unreached, -> { where(reached_at: nil) }
  scope :for_tier, ->(tier) { where(tier: tier) }

  def reached?
    reached_at.present?
  end

  # Thresholds follow the goal's target for this milestone's own tier, which
  # doubles each time a tier is cleared and moves as the community grows — so
  # they are derived rather than frozen at creation.
  def effective_threshold
    goal = season_community_goal
    (goal.base_target * (SeasonCommunityGoal::TIER_MULTIPLIER**(tier - 1)) * (percent / 100.0)).round(2)
  end
end
