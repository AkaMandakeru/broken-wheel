# frozen_string_literal: true

# Refreshes every active season's community totals, pays out milestones the
# community has just crossed, and escalates a goal to its next tier once the
# current one is cleared.
#
# Idempotency comes from stamps, not counters: a milestone fires only if its
# `reached_at` claim succeeds, and a tier advances only from the exact tier
# number the job read. Both survive the job running twice.
class AggregateCommunityGoalsJob < ApplicationJob
  queue_as :default

  def perform(season_id = nil)
    seasons = season_id ? Season.where(id: season_id) : Season.active

    seasons.find_each do |season|
      season.season_community_goals.find_each do |goal|
        Seasons::CommunityAggregator.call(goal)
        award_newly_reached(goal.reload)
        advance_tiers(goal)
      end
    end
  end

  private

  def award_newly_reached(goal)
    goal.current_milestones.unreached.each do |milestone|
      next if goal.tier_progress < milestone.effective_threshold

      # Claim first: whoever stamps reached_at owns the payout.
      claimed = SeasonCommunityMilestone.where(id: milestone.id, reached_at: nil)
                                        .update_all(reached_at: Time.current, updated_at: Time.current)
      next unless claimed.positive?

      # No user_id: this belongs to the whole community, not one runner.
      SeasonActivity.create!(
        season: goal.season,
        kind: "community_milestone",
        metadata: { goal: goal.key, percent: milestone.percent, tier: milestone.tier, title: goal.display_title }
      )

      GrantCommunityMilestoneJob.perform_later(milestone.id)
    end
  end

  # A community can clear more than one tier between runs (a bulk import, or a
  # long gap), so this loops — bounded, so a goal with a zero target can't spin.
  def advance_tiers(goal)
    advances = 0

    while goal.tier_complete? && !goal.final_tier? && advances < SeasonCommunityGoal::MAX_TIER_ADVANCES_PER_RUN
      break unless clear_tier(goal)

      advances += 1
      goal.reload
      award_newly_reached(goal)
    end
  end

  def clear_tier(goal)
    completed_tier = goal.tier
    cleared_target = goal.effective_target
    new_started_value = goal.tier_started_value.to_f + cleared_target

    # Conditional on the tier we read, so two concurrent runs can't both advance.
    claimed = SeasonCommunityGoal.where(id: goal.id, tier: completed_tier)
                                 .update_all(
                                   tier: completed_tier + 1,
                                   tier_started_value: new_started_value,
                                   updated_at: Time.current
                                 )
    return false unless claimed.positive?

    goal.reload
    # The new tier's target is sized by the community as it stands now, then
    # frozen for the duration of that tier.
    goal.freeze_tier_target!
    build_next_tier_milestones(goal, completed_tier)

    SeasonActivity.create!(
      season: goal.season,
      kind: "community_tier_cleared",
      metadata: {
        goal: goal.key, title: goal.display_title, tier: completed_tier,
        target: cleared_target, next_tier: goal.tier, next_target: goal.effective_target
      }
    )

    GrantCommunityTierJob.perform_later(goal.id, completed_tier)
    true
  end

  # The new tier repeats the previous tier's milestone percentages; thresholds
  # are derived from the tier, so they scale with the doubled target on their own.
  #
  # Deliberately without the previous tier's `season_reward`: those are one-time
  # cosmetics and badges, and re-pointing them at a new tier would only produce
  # grants the unique index rejects. Repeat tiers pay in coins instead, via
  # GrantCommunityTierJob, which scales with the tier.
  def build_next_tier_milestones(goal, completed_tier)
    percents = goal.season_community_milestones.for_tier(completed_tier).pluck(:percent)
    return if percents.empty?

    tier_target = goal.effective_target

    percents.each do |percent|
      # `threshold` is a snapshot for display; reads go through
      # SeasonCommunityMilestone#effective_threshold, which stays correct even
      # as a per-participant target grows with the community.
      goal.season_community_milestones.create!(
        tier: goal.tier, percent: percent, threshold: (tier_target * (percent.to_f / 100)).round(2)
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      next # already created by a concurrent run
    end
  end
end
