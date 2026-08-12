# frozen_string_literal: true

# End-of-season payout. Runs once when a season closes: a final recalculation
# so nothing imported late is missed, then completion-tier rewards for everyone
# who earned them.
#
# Rewards participation rather than only the podium — the 25/50/75/100% tiers
# mean a consistent beginner finishes the season with something to show.
class SeasonFinalizeJob < ApplicationJob
  queue_as :default

  def perform(season_id)
    season = Season.find_by(id: season_id)
    return unless season
    return if season.finalized_at.present?

    season.season_participations.includes(:user).find_each do |participation|
      SeasonProgressService.new(participation).recalculate
      announce(season, participation)
    end

    season.update_column(:finalized_at, Time.current)
  end

  private

  # The recalculation already granted every tier the participant qualifies for;
  # this records the season's closing note for their timeline.
  def announce(season, participation)
    SeasonActivity.create!(
      season: season,
      user: participation.user,
      kind: "season_finalized",
      metadata: {
        level: participation.level,
        xp: participation.xp,
        completion_percent: participation.completion_percent,
        medal: participation.medal_tier
      }
    )
  end
end
