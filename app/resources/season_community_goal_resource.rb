# frozen_string_literal: true

# The goal the whole community pushes toward, with the current tier's
# milestones. Amounts are in `unit` and measure only the current tier.
class SeasonCommunityGoalResource < ApplicationResource
  attributes :id, :key, :metric, :tier, :tiers_cleared, :max_tiers, :percent_complete, :tier_payout

  attribute(:title) { |goal| goal.display_title }
  attribute(:description) { |goal| goal.display_description }
  attribute(:unit) { |goal| goal.unit }
  attribute(:progress) { |goal| goal.tier_progress.to_f }
  attribute(:target) { |goal| goal.effective_target.to_f }
  attribute(:final_tier) { |goal| goal.final_tier? }
  attribute(:computed_at) { |goal| goal.computed_at&.iso8601 }

  # Clearing a tier doubles the goal, so there is always a next target.
  attribute(:next_tier_target) { |goal| (goal.effective_target * SeasonCommunityGoal::TIER_MULTIPLIER).round.to_f }

  attribute :milestones do |goal|
    goal.season_community_milestones.select { |milestone| milestone.tier == goal.tier }.map do |milestone|
      {
        id: milestone.id,
        percent: milestone.percent,
        reached: milestone.reached?,
        reached_at: milestone.reached_at&.iso8601,
        reward: milestone.season_reward && SeasonRewardResource.new(milestone.season_reward).serializable_hash
      }
    end
  end
end
