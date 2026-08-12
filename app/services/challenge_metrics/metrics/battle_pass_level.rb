# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    class BattlePassLevel < Base
      def self.call(context)
        context.participation&.level.to_i
      end

      def self.unit = "level"
    end
  end
end
