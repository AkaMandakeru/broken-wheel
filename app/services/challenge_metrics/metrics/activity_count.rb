# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    class ActivityCount < Base
      def self.call(context)
        context.workouts.size
      end

      def self.unit = "activities"
    end
  end
end
