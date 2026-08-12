# frozen_string_literal: true

module DailyChallenges
  # Marks daily assignments complete and stamps the XP they paid.
  #
  # Today and yesterday are both evaluated: Strava imports routinely land hours
  # after the run, and a daily that expired at midnight because the data was
  # late would read as a bug to the user who actually did the work.
  class Evaluator
    GRACE_DAYS = 1

    def initialize(participation, context: nil)
      @participation = participation
      @user = participation.user
      @season = participation.season
      @context = context
    end

    def call
      assignments = pending_assignments
      return [] if assignments.empty?

      assignments.select { |assignment| complete_if_met(assignment) }
    end

    private

    def pending_assignments
      DailyChallengeAssignment
        .where(user_id: @user.id, season_id: @season.id, challenge_date: evaluated_dates)
        .pending
        .includes(:daily_challenge_template)
        .to_a
    end

    def evaluated_dates
      today = @season.current_date
      (today - GRACE_DAYS)..today
    end

    def complete_if_met(assignment)
      template = assignment.daily_challenge_template
      return false unless template.satisfied_by?(assignment.progress_in(context))

      award(assignment, template)
      true
    end

    # The caller's preloaded history when a season recalculation supplies one,
    # so evaluating three dailies costs one read rather than three.
    def context
      @context ||= ChallengeMetrics::Context.new(
        user: @user, window: @season.date_window,
        season: @season, participation: @participation
      )
    end

    def award(assignment, template)
      assignment.update!(
        completed_at: Time.current,
        xp_awarded: template.xp_reward,
        coin_awarded: template.coin_reward
      )

      Wallet.credit(
        @user,
        amount: template.coin_reward,
        reason: "daily_challenge",
        reason_key: "daily_challenge:#{assignment.id}",
        metadata: { season_id: @season.id, daily: template.key }
      )

      SeasonActivity.create!(
        season: @season,
        user: @user,
        kind: "daily_completed",
        metadata: { daily: template.display_title, xp: template.xp_reward }
      )
    end
  end
end
