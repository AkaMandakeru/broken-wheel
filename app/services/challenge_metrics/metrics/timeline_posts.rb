# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # Workouts shared to a challenge timeline — the data-backed stand-in for
    # "run with a friend", which no provider reports reliably.
    class TimelinePosts < Base
      def self.call(context)
        scope = context.user.timeline_posts
        scope = scope.where(created_at: context.window_start.beginning_of_day..context.window_end.end_of_day) if context.window
        scope.count
      end

      def self.unit = "posts"
    end
  end
end
