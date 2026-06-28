# frozen_string_literal: true

class RecomputeChallengeProgress
  def initialize(participation)
    @participation = participation
    @challenge = participation.challenge
    @user = participation.user
  end

  def call
    @participation.update!(progress_value: computed_progress)
    award_completion if newly_completed?
    @participation
  end

  private

  def computed_progress
    case @challenge.target_unit
    when "km"
      qualifying_workouts.sum(:distance_km)
    when "times"
      qualifying_workouts.count
    else
      qualifying_workouts.sum(:duration_minutes).to_f / 60
    end
  end

  # Every workout the user logged that fits this challenge's window and sport —
  # regardless of which challenge it was "assigned" to. This lets a single
  # workout count toward every challenge it qualifies for.
  def qualifying_workouts
    window = @challenge.workout_window
    scope = window ? @user.workouts.where(workout_date: window) : @user.workouts.none
    scope = scope.where(sport: @challenge.sport) if @challenge.sport.present?
    scope
  end

  def newly_completed?
    @participation.progress_value.to_f >= @challenge.target_value.to_f && @participation.completed_at.nil?
  end

  def award_completion
    @participation.update!(completed_at: Time.current)
    record_season_completions

    badge = completion_badge
    return if @user.user_badges.exists?(badge: badge, challenge: @challenge)

    @user.user_badges.create!(badge: badge, challenge: @challenge, earned_at: Time.current)
  end

  # Capture completion durably for every active season that includes this
  # challenge, so season XP survives weekly challenge resets. Then recompute.
  def record_season_completions
    SeasonChallenge.joins(:season)
                   .where(challenge_id: @challenge.id, seasons: { status: "active" })
                   .find_each do |season_challenge|
      participation = SeasonProgressService.ensure_participation(@user, season_challenge.season)
      next if participation.season_challenge_completions.exists?(season_challenge: season_challenge)

      begin
        participation.season_challenge_completions.create!(
          season_challenge: season_challenge,
          xp_awarded: season_challenge.xp_reward,
          completed_at: Time.current
        )
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        next # already recorded by a concurrent recalc
      end

      SeasonActivity.create!(
        season: season_challenge.season,
        user: @user,
        kind: "challenge_completed",
        metadata: { challenge: @challenge.display_title, xp: season_challenge.xp_reward }
      )
      SeasonRecalcJob.perform_later(@user.id, season_challenge.season_id)
    end
  end

  def completion_badge
    Badge.find_or_create_by!(name: "Completed: #{@challenge.title}") do |b|
      b.icon = "🏆"
      b.description = "Completed #{@challenge.title}"
      b.badge_type = "challenge_completion"
    end
  end
end
