# frozen_string_literal: true

# Enrolls a user in a challenge (idempotent) and back-fills their existing
# workouts in the challenge window — the same logic a manual "join" performs,
# so it can be reused for automatic season enrollment.
class ChallengeEnroller
  def self.call(user, challenge)
    new(user, challenge).call
  end

  def initialize(user, challenge)
    @user = user
    @challenge = challenge
  end

  def call
    existing = @user.challenge_participations.find_by(challenge_id: @challenge.id)
    return existing if existing

    participation = @user.challenge_participations.create!(challenge: @challenge)
    backfill(participation)
    participation
  end

  private

  def backfill(participation)
    window = @challenge.workout_window
    workouts = window ? @user.workouts.where(workout_date: window) : @user.workouts.none
    workouts = workouts.where(sport: @challenge.sport) if @challenge.sport.present?
    to_assign = workouts.where(challenge_participation_id: nil)
    return unless to_assign.exists?

    to_assign.update_all(challenge_participation_id: participation.id)
    RecomputeChallengeProgress.new(participation).call
  end
end
