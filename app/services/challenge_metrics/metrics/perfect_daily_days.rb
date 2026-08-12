# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # Days on which every assigned daily challenge was completed — the basis of
    # the "Perfect Month" secret.
    #
    # Only days the user was actually assigned challenges count. Someone who
    # joins on the 11th is judged on the 11th onward, never on days that were
    # never offered to them.
    class PerfectDailyDays < Base
      def self.call(context)
        return 0 if context.season.nil?

        rows = DailyChallengeAssignment.where(user_id: context.user.id, season_id: context.season.id)
                                       .where(challenge_date: ..last_judged_date(context))
                                       .pluck(:challenge_date, :completed_at)
        return 0 if rows.empty?

        rows.group_by(&:first).count { |_date, day| day.all? { |(_d, completed_at)| completed_at.present? } }
      end

      def self.unit = "days"

      # Today is still in play — judging it would mark the month imperfect the
      # moment it begins.
      def self.last_judged_date(context)
        context.season.current_date - 1
      end

      private_class_method :last_judged_date
    end
  end
end
