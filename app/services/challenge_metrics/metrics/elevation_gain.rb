# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    class ElevationGain < Base
      def self.call(context)
        context.workouts.sum { |w| w.elevation_gain_m.to_f }.round(1)
      end

      def self.unit = "m"
    end
  end
end
