# frozen_string_literal: true

# Recomputes one challenge participation from the user's workouts. Every
# requirement is evaluated through ChallengeMetrics; the challenge completes only
# when all of them are satisfied.
#
# Idempotent: progress is always derived, never incremented, so this can run as
# often as needed. Completion is recorded once and never revoked.
#
# A participation belongs to at most one season, and is scored over that season's
# window — so the same challenge reused in a later season is measured against the
# new season's dates and starts from zero.
class RecomputeChallengeProgress
  def initialize(participation, context: nil)
    @participation = participation
    @challenge = participation.challenge
    @user = participation.user
    @shared_context = context
  end

  def call
    requirements = @challenge.challenge_requirements.to_a
    return legacy_recompute if requirements.empty?

    values = requirements.index_with { |requirement| evaluate(requirement) }

    @participation.update!(
      requirement_progress: values.transform_keys { |r| r.id.to_s },
      progress_value: headline_value(requirements, values)
    )

    award_completion if newly_completed?(requirements, values)
    @participation
  end

  private

  def evaluate(requirement)
    ChallengeMetrics.call(requirement.metric, context_for(requirement))
  end

  # Reuses the caller's preloaded workout history when a season recalculation
  # supplies one, so twenty challenges cost one read rather than twenty.
  def context_for(requirement)
    if @shared_context
      @shared_context.rescope(window: window, options: requirement.options, sport: @challenge.sport.presence)
    else
      ChallengeMetrics::Context.new(
        user: @user,
        window: window,
        options: requirement.options,
        sport: @challenge.sport.presence,
        season: season,
        participation: season_participation
      )
    end
  end

  def window
    @window ||= @participation.window
  end

  def season_challenge
    @season_challenge ||= @participation.season_challenge
  end

  def season
    @season ||= @participation.season
  end

  def season_participation
    return @season_participation if defined?(@season_participation)

    @season_participation = season && @user.season_participations.find_by(season_id: season.id)
  end

  def headline_value(requirements, values)
    primary = requirements.first
    value = values[primary]
    # `lte` goals (a target time) have no meaningful partial value on a 0→target
    # bar, so the headline reports the target once met and nothing before.
    return primary.satisfied_by?(value) ? primary.target : 0 if primary.comparator == "lte"

    value.to_f
  end

  def newly_completed?(requirements, values)
    return false if @participation.completed_at.present?

    requirements.all? { |requirement| requirement.satisfied_by?(values[requirement]) }
  end

  # Pre-requirement challenges (none should remain after the backfill, but an
  # admin can still create one) keep the original single-target behaviour.
  def legacy_recompute
    @participation.update!(progress_value: legacy_progress)
    award_completion if @participation.progress_value.to_f >= @challenge.target_value.to_f && @participation.completed_at.nil?
    @participation
  end

  def legacy_progress
    scope = window ? @user.workouts.where(workout_date: window) : @user.workouts.none
    scope = scope.where(sport: @challenge.sport) if @challenge.sport.present?

    case @challenge.target_unit
    when "km"    then scope.sum(:distance_km)
    when "times" then scope.count
    else              scope.sum(:duration_minutes).to_f / 60
    end
  end

  def award_completion
    @participation.update!(completed_at: Time.current)
    record_season_completion

    badge = completion_badge
    return if @user.user_badges.exists?(badge: badge, challenge: @challenge)

    @user.user_badges.create!(badge: badge, challenge: @challenge, earned_at: Time.current)
  end

  # Capture completion durably for this participation's own season, so season XP
  # survives weekly challenge resets. Standalone participations credit no season.
  def record_season_completion
    return if season_challenge.nil? || !season.active?

    participation = SeasonProgressService.ensure_participation(@user, season)

    # Elite content still accrues progress below its unlock level; it just
    # doesn't pay out until the participant reaches it.
    return if season_challenge.locked_for?(participation)
    return if participation.season_challenge_completions.exists?(season_challenge: season_challenge)

    begin
      participation.season_challenge_completions.create!(
        season_challenge: season_challenge,
        xp_awarded: season_challenge.xp_reward,
        completed_at: Time.current
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      return # already recorded by a concurrent recalc
    end

    credit_coins(participation)

    SeasonActivity.create!(
      season: season,
      user: @user,
      kind: season_challenge.hidden? ? "secret_discovered" : "challenge_completed",
      metadata: { challenge: @challenge.display_title, xp: season_challenge.xp_reward, category: season_challenge.category }
    )
    SeasonRecalcJob.enqueue_debounced(@user.id, season.id)
  end

  def credit_coins(participation)
    return if season_challenge.coin_reward.zero?

    Wallet.credit(
      @user,
      amount: season_challenge.coin_reward,
      reason: "season_challenge",
      reason_key: "season_challenge:#{season_challenge.id}:#{participation.id}",
      metadata: { season_id: season.id, challenge: @challenge.display_title }
    )
  end

  def completion_badge
    Badge.find_or_create_by!(name: "Completed: #{@challenge.title}") do |b|
      b.icon = "🏆"
      b.description = "Completed #{@challenge.title}"
      b.badge_type = "challenge_completion"
    end
  end
end
