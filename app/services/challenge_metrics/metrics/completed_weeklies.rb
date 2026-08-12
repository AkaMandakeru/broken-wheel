# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # Weekly season challenges the participant has finished — powers
    # "The Collector: complete all weekly challenges".
    class CompletedWeeklies < Base
      def self.call(context)
        participation = context.participation
        return 0 if participation.nil?

        weekly_ids = context.season.weekly_challenges.pluck(:id)
        return 0 if weekly_ids.empty?

        participation.season_challenge_completions.where(season_challenge_id: weekly_ids).count
      end

      def self.unit = "challenges"
    end
  end
end
