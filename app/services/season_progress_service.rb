# frozen_string_literal: true

# Recomputes a user's season progress from scratch (idempotent). XP comes from
# the durable completion ledgers plus time-based bonuses, so it survives weekly
# challenge resets and can be re-run safely at any time.
#
# One workout history is loaded here and shared with every challenge, objective
# and daily evaluated below — a recalculation that let each metric issue its own
# query would cost hundreds of round trips.
class SeasonProgressService
  WORKOUT_XP              = 20
  STREAK_XP_PER_WEEK      = 10
  STREAK_CAP_WEEKS        = 10
  CONSISTENCY_XP_PER_WEEK = 15
  CLUB_BONUS              = 25

  def self.ensure_participation(user, season)
    season.season_participations.find_or_create_by!(user: user)
  rescue ActiveRecord::RecordNotUnique
    season.season_participations.find_by!(user: user)
  end

  def initialize(participation)
    @participation = participation
    @user = participation.user
    @season = participation.season
  end

  def recalculate
    # Record everything newly completed before summing the ledgers.
    SeasonObjectives.evaluate(@participation, context: context)
    DailyChallenges::Evaluator.new(@participation, context: context).call

    stats = compute_stats
    old_level = @participation.level
    total = total_xp
    new_level = @season.level_curve_object.level_for(total)

    @participation.update!(
      stats.merge(
        xp: total,
        level: new_level,
        xp_breakdown: xp_breakdown,
        last_recalculated_at: Time.current
      )
    )

    sync_lifetime_xp
    grant_parallel_rewards
    handle_level_up(old_level, new_level) if new_level > old_level
    @participation
  end

  private

  # The season's workouts, loaded once and shared with every challenge,
  # objective, daily and stat evaluated below.
  def context
    @context ||= ChallengeMetrics::Context.new(
      user: @user,
      window: @season.date_window,
      season: @season,
      participation: @participation
    )
  end

  # --- XP ---------------------------------------------------------------------

  def xp_components
    @xp_components ||= {
      # Only claimed challenge XP counts toward the bar — completing a challenge
      # sets it aside, collecting it is what moves the total.
      challenges: @participation.season_challenge_completions.claimed.sum(:xp_awarded),
      objectives: @participation.season_objective_completions.sum(:xp_awarded),
      dailies: daily_xp,
      workouts: workouts_xp,
      streak: [ streak_weeks, STREAK_CAP_WEEKS ].min * STREAK_XP_PER_WEEK,
      consistency: consistency_weeks * CONSISTENCY_XP_PER_WEEK,
      clubs: @user.club_memberships.exists? ? CLUB_BONUS : 0
    }
  end

  def total_xp
    (xp_components.values.sum * @season.xp_multiplier).round
  end

  def xp_breakdown
    xp_components.merge(multiplier: @season.xp_multiplier.to_f)
  end

  def daily_xp
    DailyChallengeAssignment.where(user_id: @user.id, season_id: @season.id).sum(:xp_awarded)
  end

  # Every workout inside the season earns base XP, multiplied by whatever boost
  # was active on the day it happened. Applying the boost per workout (rather
  # than to the total) is what keeps recompute-from-scratch honest: an expired
  # boost stops paying, and a new one never inflates the past.
  def workouts_xp
    boosts = @user.user_xp_boosts.to_a
    season_workout_dates.sum do |date|
      multiplier = boosts.select { |b| b.covers_date?(date) }.map(&:multiplier).max&.to_f || 1.0
      (WORKOUT_XP * multiplier).round
    end
  end

  # One row per workout, not per day — XP is earned per workout, and a runner
  # who trains twice in a day earns twice.
  #
  # Read from the shared context rather than re-querying: this service loads the
  # season's workouts once precisely so nothing below has to go back to the
  # database, and the XP path was the one place still doing so.
  def season_workout_dates
    @season_workout_dates ||= context.workouts.filter_map(&:workout_date)
  end

  def streak_weeks
    AchievementChecker.user_stats(@user)[:streak].to_i
  end

  def consistency_weeks
    season_workout_dates.map { |d| d.beginning_of_week(:sunday) }.uniq.size
  end

  # --- Denormalised stats (power the six leaderboards and the season page) -----

  def compute_stats
    workouts = context.workouts

    {
      total_distance_km: workouts.sum { |w| w.distance_km.to_f }.round(2),
      activities_count: workouts.size,
      elevation_gain_m: workouts.sum { |w| w.elevation_gain_m.to_f }.round(1),
      longest_streak_days: ChallengeMetrics.call("consecutive_days", context),
      best_5k_seconds: ChallengeMetrics.call("fastest_5k_seconds", context),
      medal_fragments: earned_fragments,
      coins_earned: season_coins_earned,
      completion_percent: completion_percent
    }
  end

  def earned_fragments
    challenge_fragments = SeasonChallenge
                          .joins(:season_challenge_completions)
                          .where(season_challenge_completions: { season_participation_id: @participation.id })
                          .where.not(season_challenge_completions: { claimed_at: nil })
                          .sum(:fragment_reward)

    objective_fragments = SeasonObjective
                          .joins(:season_objective_completions)
                          .where(season_objective_completions: { season_participation_id: @participation.id })
                          .sum(:fragment_reward)

    challenge_fragments + objective_fragments
  end

  def season_coins_earned
    @user.coin_transactions.credits.where("metadata ->> 'season_id' = ?", @season.id.to_s).sum(:amount)
  end

  # Share of the season's plannable content finished. Secrets are excluded from
  # the denominator on purpose — a player cannot aim at a challenge they have
  # not been told exists, so counting them would make 100% unreachable by design.
  def completion_percent
    total = @season.season_challenges.visible.count + @season.season_objectives.count
    return 0 if total.zero?

    done = @participation.season_challenge_completions
                         .joins(:season_challenge)
                         .where(season_challenges: { hidden: false })
                         .count +
           @participation.season_objective_completions.count

    [ ((done.to_f / total) * 100).round, 100 ].min
  end

  # --- Rewards ----------------------------------------------------------------

  def grant_parallel_rewards
    granter = SeasonRewardGranter.new(@participation)
    granter.grant_for_level(@participation.level)
    granter.grant_for_unlock("legacy", completed_legacy_missions)
    granter.grant_for_unlock("completion_tier", @participation.completion_percent)
    granter.grant_for_unlock("medal_fragments", @participation.medal_fragments)
  end

  def completed_legacy_missions
    @participation.season_objective_completions
                  .joins(:season_objective)
                  .where(season_objectives: { track: "legacy" })
                  .count
  end

  def sync_lifetime_xp
    @user.update_column(:lifetime_xp, @user.season_participations.sum(:xp))
  end

  def handle_level_up(_old_level, new_level)
    SeasonActivity.create!(season: @season, user: @user, kind: "level_up", metadata: { level: new_level })
    notify_level_up(new_level)
  end

  def notify_level_up(level)
    PushNotifier.notify(
      @user,
      title: I18n.t("push.season_level.title"),
      body: I18n.t("push.season_level.body", level: level, season: @season.name),
      path: Rails.application.routes.url_helpers.season_path(@season),
      tag: "season-#{@season.id}-level"
    )
  end
end
