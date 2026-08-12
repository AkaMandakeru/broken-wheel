# frozen_string_literal: true

# Hands every active participant their three daily challenges for the day.
# Runs just after midnight in the season's own timezone; the assignment itself
# is deterministic, so a retry or a lazy page visit produces the same set.
class AssignDailyChallengesJob < ApplicationJob
  queue_as :default

  def perform(season_id = nil)
    seasons = season_id ? Season.where(id: season_id) : Season.active
    seasons.find_each do |season|
      next unless season.daily_challenge_templates.active.exists? ||
                  DailyChallengeTemplate.active.where(season_id: nil).exists?

      season.season_participations.includes(:user).find_each do |participation|
        DailyChallenges::Assigner.call(participation.user, season)
      end
    end
  end
end
