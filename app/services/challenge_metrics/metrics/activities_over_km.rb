# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # Counts activities of at least `km`. Options: { km: 10 }
    class ActivitiesOverKm < Base
      def self.call(context)
        threshold = context.option(:km, 10).to_f
        context.workouts.count { |w| w.distance_km.to_f >= threshold }
      end

      def self.unit = "activities"
    end
  end
end
