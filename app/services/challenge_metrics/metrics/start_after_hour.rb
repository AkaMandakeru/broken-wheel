# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # Activities started at or after a local wall-clock time.
    # Options: { hour: 18, minute: 0 }
    class StartAfterHour < Base
      def self.call(context)
        cutoff = (context.option(:hour, 18).to_i * 60) + context.option(:minute, 0).to_i
        timed(context).count { |w| w.start_minute_of_day >= cutoff }
      end

      def self.unit = "activities"

      def self.requires_start_time? = true
    end
  end
end
