# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # Activities logged in the window while the user belongs to a club.
    class ClubWorkoutCount < Base
      def self.call(context)
        return 0 unless context.user.club_memberships.exists?

        context.workouts.size
      end

      def self.unit = "activities"
    end
  end
end
