# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    class DailyChallengesDone < Base
      def self.call(context)
        return 0 if context.season.nil?

        DailyChallengeAssignment.where(user_id: context.user.id, season_id: context.season.id)
                                .completed
                                .count
      end

      def self.unit = "challenges"
    end
  end
end
