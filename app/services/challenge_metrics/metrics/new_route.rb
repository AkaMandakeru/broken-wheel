# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # Activities on a route the user had never run before. Relies on the GPS
    # summary polyline, so activities without one (manual entries, treadmill)
    # never count.
    class NewRoute < Base
      def self.call(context)
        seen = context.workouts_before_window.filter_map(&:route_signature).to_set
        count = 0

        context.workouts.sort_by { |w| [ w.workout_date, w.start_minute_of_day.to_i ] }.each do |workout|
          signature = workout.route_signature
          next if signature.blank?
          next if seen.include?(signature)

          seen << signature
          count += 1
        end

        count
      end

      def self.unit = "activities"
    end
  end
end
