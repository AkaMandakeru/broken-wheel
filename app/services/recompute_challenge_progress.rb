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
    badge = completion_badge
    return if @user.user_badges.exists?(badge: badge, challenge: @challenge)

    @user.user_badges.create!(badge: badge, challenge: @challenge, earned_at: Time.current)
  end

  def completion_badge
    Badge.find_or_create_by!(name: "Completed: #{@challenge.title}") do |b|
      b.icon = "🏆"
      b.description = "Completed #{@challenge.title}"
      b.badge_type = "challenge_completion"
    end
  end
end
