# frozen_string_literal: true

module Workouts
  # A workout the player typed in, from the web form or the app. Takes the
  # model's *_input attributes so Workout's own callbacks normalise distance,
  # duration and start time.
  #
  # Season XP is not credited here: Workout#after_create_commit enqueues the
  # debounced SeasonRecalcJob, so the caller only learns that XP is pending.
  class ManualEntry
    def initialize(user, attributes)
      @user = user
      @attributes = attributes
    end

    # Returns the workout; check `persisted?` for success, `errors` otherwise.
    def call
      workout = @user.workouts.build(@attributes.to_h.merge(provider: "manual"))
      return workout unless workout.save(context: :manual_entry)

      Analytics.track(user: @user, event: "workout_created_manually",
                      properties: { sport: workout.sport, distance_km: workout.distance_km,
                                    duration_minutes: workout.duration_minutes })
      recompute_challenge_progress
      workout
    end

    private

    # Every active challenge the user is in — a workout counts toward all
    # challenges it qualifies for, not just the one it was attached to.
    def recompute_challenge_progress
      @user.challenge_participations
           .joins(:challenge)
           .where(challenges: { status: "active" }, completed_at: nil)
           .find_each { |participation| RecomputeChallengeProgress.new(participation).call }
    end
  end
end
