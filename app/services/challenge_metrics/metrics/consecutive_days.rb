# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # Longest run of back-to-back calendar days with at least one activity.
    class ConsecutiveDays < Base
      def self.call(context)
        dates = context.dates
        return 0 if dates.empty?

        longest = 1
        current = 1
        dates.each_cons(2) do |previous, following|
          if (following - previous).to_i == 1
            current += 1
            longest = [ longest, current ].max
          else
            current = 1
          end
        end
        longest
      end

      def self.unit = "days"
    end
  end
end
