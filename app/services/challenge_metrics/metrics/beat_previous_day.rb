# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # 1 once any day inside the window beat the immediately preceding calendar
    # day's total distance. The previous day is read from full history, so the
    # first day of a window can still qualify.
    class BeatPreviousDay < Base
      def self.call(context)
        totals = context.distance_by_date
        return 0 if totals.empty?

        history_totals = context.history
                                .select { |w| w.workout_date.present? }
                                .group_by(&:workout_date)
                                .transform_values { |ws| ws.sum { |w| w.distance_km.to_f } }

        beaten = totals.any? do |date, distance|
          previous = history_totals[date - 1].to_f
          previous.positive? && distance > previous
        end

        beaten ? 1 : 0
      end

      def self.unit = "boolean"
    end
  end
end
