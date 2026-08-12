# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    class ActiveDays < Base
      def self.call(context)
        context.dates.size
      end

      def self.unit = "days"
    end
  end
end
