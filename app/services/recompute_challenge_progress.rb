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
      @participation.workouts.sum(:distance_km)
    when "times"
      @participation.workouts.count
    else
      @participation.workouts.sum(:duration_minutes).to_f / 60
    end
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
      completion = participation.season_challenge_completions.find_or_initialize_by(season_challenge: season_challenge)
      next if completion.persisted?

      completion.update!(xp_awarded: season_challenge.xp_reward, completed_at: Time.current)
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
