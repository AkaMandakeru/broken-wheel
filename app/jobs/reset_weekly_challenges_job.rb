# frozen_string_literal: true

# Resets every active weekly challenge at the start of a new week:
#   - Rolls `starts_at` / `ends_at` to the current Sun–Sat window.
#   - Zeroes each participation's `progress_value` and clears `completed_at`.
#   - Detaches workouts previously counted, since progress is recomputed from
#     `participation.workouts` when users log new workouts for the week.
#
# Scheduled via config/recurring.yml to run every Sunday at 11:59 PM.
class ResetWeeklyChallengesJob < ApplicationJob
  queue_as :default

  def perform
    week = Challenge.current_week_window

    Challenge.where(challenge_type: "weekly", status: "active").find_each do |challenge|
      Challenge.transaction do
        participation_ids = challenge.challenge_participations.pluck(:id)

        if participation_ids.any?
          Workout.where(challenge_participation_id: participation_ids)
                 .update_all(challenge_participation_id: nil)

          ChallengeParticipation.where(id: participation_ids)
                                .update_all(progress_value: 0, completed_at: nil, updated_at: Time.current)
        end

        challenge.update!(starts_at: week.begin, ends_at: week.end)
      end
    end
  end
end
