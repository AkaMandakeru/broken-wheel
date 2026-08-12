# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    class DurationHours < Base
      def self.call(context)
        seconds = context.workouts.sum { |w| w.moving_time_seconds.presence || (w.duration_minutes.to_i * 60) }
        (seconds / 3600.0).round(2)
      end

      def self.unit = "hours"
    end
  end
end
