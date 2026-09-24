# frozen_string_literal: true

# Hands a participation reward to everyone in the season who already qualifies.
#
# The automatic path only reaches a participant when something recalculates
# them, so a reward added mid-season would otherwise sit there until each member
# happened to train. This is the "give it to them now" button behind that.
#
# It applies exactly the same rule as the automatic path rather than a looser
# one, so pressing the button can never hand the reward to someone the season
# page would say is outside the window.
class DistributeSeasonRewardJob < ApplicationJob
  queue_as :default

  def perform(season_reward_id)
    reward = SeasonReward.find_by(id: season_reward_id)
    # A claimable reward is offered in the locker, not pushed from here.
    return unless reward&.participation?
    return if reward.claimable?

    reward.season.season_participations.find_each do |participation|
      next unless reward.covers_join?(participation.created_at)
      next if reward.premium? && !participation.premium?

      SeasonRewardGranter.new(participation).grant_reward(reward)
    end
  end
end
