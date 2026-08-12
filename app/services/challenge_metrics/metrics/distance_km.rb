# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    class DistanceKm < Base
      def self.call(context)
        context.workouts.sum { |w| w.distance_km.to_f }.round(2)
      end

      def self.unit = "km"
    end
  end
end
