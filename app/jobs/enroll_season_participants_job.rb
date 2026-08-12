# frozen_string_literal: true

# Enrolls everyone already participating in a season into a challenge that was
# just added to it, then refreshes their season XP.
class EnrollSeasonParticipantsJob < ApplicationJob
  queue_as :default

  def perform(season_challenge_id)
    season_challenge = SeasonChallenge.find_by(id: season_challenge_id)
    return unless season_challenge

    season_challenge.season.season_participations.find_each do |participation|
      ChallengeEnroller.call(participation.user, season_challenge.challenge, season: season_challenge.season)
      SeasonRecalcJob.enqueue_debounced(participation.user_id, season_challenge.season_id)
    end
  end
end
