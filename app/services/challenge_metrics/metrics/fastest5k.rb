# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # Best projected 5 km time, in seconds, across activities of at least 5 km.
    # Lower is better, so this metric compares with :lte.
    class Fastest5k < Base
      DISTANCE_KM = 5.0

      def self.call(context)
        context.workouts
               .select { |w| w.distance_km.to_f >= DISTANCE_KM }
               .filter_map(&:pace_seconds_per_km)
               .map { |pace| (pace * DISTANCE_KM).round }
               .min
      end

      def self.unit = "seconds"

      def self.comparator = :lte
    end
  end
end
