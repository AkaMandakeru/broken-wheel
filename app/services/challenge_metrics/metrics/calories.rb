# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    class Calories < Base
      def self.call(context)
        context.workouts.sum { |w| w.calories.to_i }
      end

      def self.unit = "kcal"
    end
  end
end
