# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    class ClubMember < Base
      def self.call(context)
        context.user.club_memberships.exists? ? 1 : 0
      end

      def self.unit = "boolean"
    end
  end
end
