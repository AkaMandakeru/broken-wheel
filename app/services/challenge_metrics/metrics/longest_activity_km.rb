# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    class LongestActivityKm < Base
      def self.call(context)
        context.workouts.map { |w| w.distance_km.to_f }.max.to_f.round(2)
      end

      def self.unit = "km"
    end
  end
end
