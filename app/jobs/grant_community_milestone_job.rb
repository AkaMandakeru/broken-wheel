# frozen_string_literal: true

# Pays a reached community milestone out to every participant. Grants go through
# SeasonRewardGranter, whose unique index makes a repeat run a no-op.
class GrantCommunityMilestoneJob < ApplicationJob
  include GrantsToSeasonParticipants

  queue_as :default

  def perform(milestone_id, after_id = nil)
    milestone = SeasonCommunityMilestone.find_by(id: milestone_id)
    return unless milestone&.season_reward

    season = milestone.season_community_goal.season
    each_participant_batch(season, after_id, milestone_id) do |participation|
      grant(participation, milestone.season_reward)
    end
  end

  private

  def grant(participation, reward)
    SeasonRewardGranter.new(participation).grant_for_unlock("community", reward.unlock_value.to_i)
  end
end
