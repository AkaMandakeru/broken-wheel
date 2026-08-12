# frozen_string_literal: true

# Enrolls a user in a challenge (idempotent) and back-fills their existing
# workouts in the challenge window — the same logic a manual "join" performs,
# so it can be reused for automatic season enrollment.
#
# Enrollment is scoped to a season. The same challenge used in two seasons gives
# a user two participations, so a new season always starts empty rather than
# inheriting the previous season's progress.
class ChallengeEnroller
  def self.call(user, challenge, season: nil)
    new(user, challenge, season: season).call
  end

  def initialize(user, challenge, season: nil)
    @user = user
    @challenge = challenge
    @season = season
  end

  def call
    existing = @user.challenge_participations.find_by(challenge_id: @challenge.id, season_id: @season&.id)
    return existing if existing

    participation = @user.challenge_participations.create!(challenge: @challenge, season: @season)
    backfill(participation)
    participation
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Created by a concurrent enrolment.
    @user.challenge_participations.find_by(challenge_id: @challenge.id, season_id: @season&.id)
  end

  private

  def backfill(participation)
    window = participation.window
    workouts = window ? @user.workouts.where(workout_date: window) : @user.workouts.none
    workouts = workouts.where(sport: @challenge.sport) if @challenge.sport.present?

    # Only claim workouts nothing else has taken; the attribution column is for
    # display, and progress is recomputed from every qualifying workout anyway.
    to_assign = workouts.where(challenge_participation_id: nil)
    to_assign.update_all(challenge_participation_id: participation.id) if to_assign.exists?

    RecomputeChallengeProgress.new(participation).call
  end
end
