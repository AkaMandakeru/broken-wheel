# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # Distinct calendar weeks touched — "run at least once every week of August".
    class WeeksWithActivity < Base
      def self.call(context)
        context.dates.map { |d| d.beginning_of_week(:sunday) }.uniq.size
      end

      def self.unit = "weeks"
    end
  end
end
