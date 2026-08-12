# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # 1 once the window contains a performance better than anything the user had
    # logged before the window opened. Options: { kind: "distance" | "pace" }
    #
    # A user with no prior history cannot set a record — otherwise a first-ever
    # workout would silently complete the goal.
    class PersonalRecord < Base
      def self.call(context)
        case context.option(:kind, "distance").to_s
        when "pace" then pace_record(context)
        else             distance_record(context)
        end
      end

      def self.unit = "boolean"

      def self.distance_record(context)
        previous_best = context.workouts_before_window.map { |w| w.distance_km.to_f }.max
        return 0 if previous_best.nil? || previous_best.zero?

        best = context.workouts.map { |w| w.distance_km.to_f }.max.to_f
        best > previous_best ? 1 : 0
      end

      def self.pace_record(context)
        previous_best = context.workouts_before_window.filter_map(&:pace_seconds_per_km).min
        return 0 if previous_best.nil?

        best = context.workouts.filter_map(&:pace_seconds_per_km).min
        best.present? && best < previous_best ? 1 : 0
      end

      private_class_method :distance_record, :pace_record
    end
  end
end
