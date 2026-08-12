# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # Activities finished without stopping: elapsed time never drifted from
    # moving time. Options: { min_km: 0 } to require a minimum distance.
    class UninterruptedActivity < Base
      def self.call(context)
        minimum = context.option(:min_km, 0).to_f
        context.workouts.count { |w| w.distance_km.to_f >= minimum && w.uninterrupted? }
      end

      def self.unit = "activities"
    end
  end
end
