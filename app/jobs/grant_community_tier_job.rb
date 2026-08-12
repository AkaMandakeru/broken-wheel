# frozen_string_literal: true

# Pays every participant for a cleared community tier. The payout scales with
# the tier, so a doubled goal is worth doubling down on.
#
# Coins go through the wallet ledger, whose unique (user, reason_key) index —
# keyed by goal and tier — makes a repeat run a no-op rather than free currency.
class GrantCommunityTierJob < ApplicationJob
  include GrantsToSeasonParticipants

  queue_as :default

  def perform(goal_id, tier, after_id = nil)
    goal = SeasonCommunityGoal.find_by(id: goal_id)
    return unless goal

    payout = goal.tier_coin_reward * tier
    return if payout <= 0

    each_participant_batch(goal.season, after_id, goal_id, tier) do |participation|
      credit(participation, goal, tier, payout)
    end
  end

  private

  def credit(participation, goal, tier, payout)
    Wallet.credit(
      participation.user,
      amount: payout,
      reason: "community_tier",
      reason_key: "community_tier:#{goal.id}:#{tier}",
      metadata: { season_id: goal.season_id, goal: goal.key, tier: tier }
    )
  end
end
