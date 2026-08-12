# frozen_string_literal: true

# Resets recurring weekly challenges at the start of a new week:
#   - Rolls `starts_at` / `ends_at` to the current Sun–Sat window.
#   - Zeroes each participation's `progress_value` and clears `completed_at`.
#   - Detaches workouts previously counted, since progress is recomputed from
#     the user's workouts when they log new ones for the week.
#
# Season content is deliberately excluded. A season's "Week 1 — The Beginning"
# is a fixed, one-off challenge with its own dates; rolling its window forward
# would erase the week the moment it ended. Those are seeded as `custom`
# challenges, and the season guard below is the second line of defence.
#
# Scheduled via config/recurring.yml to run every Sunday at 11:59 PM.
class ResetWeeklyChallengesJob < ApplicationJob
  queue_as :default

  def perform
    week = Challenge.current_week_window

    recurring_weekly_challenges.find_each do |challenge|
      Challenge.transaction do
        participation_ids = challenge.challenge_participations.standalone.pluck(:id)

        if participation_ids.any?
          Workout.where(challenge_participation_id: participation_ids)
                 .update_all(challenge_participation_id: nil)

          # A Hash, not the string "{}" — update_all serialises through the jsonb
          # type, and a string would be stored as the JSON value "{}".
          ChallengeParticipation.where(id: participation_ids)
                                .update_all(progress_value: 0, completed_at: nil,
                                            requirement_progress: {}, updated_at: Time.current)
        end

        challenge.update!(starts_at: week.begin, ends_at: week.end)
      end
    end
  end

  private

  def recurring_weekly_challenges
    Challenge.where(challenge_type: "weekly", status: "active")
             .where.missing(:season_challenges)
  end
end
