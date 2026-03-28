# frozen_string_literal: true

class WorkoutsController < ApplicationController
  before_action :authenticate_user!

  def index
    @participations = current_user.challenge_participations.joins(:challenge).where(challenges: { status: "active" }).includes(:challenge)
    @workouts = current_user.workouts.order(workout_date: :desc).limit(20)
    @workout_count = current_user.workouts.count
    @unique_days = current_user.workouts.distinct.count(:workout_date)
  end

  def create
    workout = current_user.workouts.build(workout_params.merge(provider: "manual"))
    if workout.save
      update_participation_progress(workout)
      newly_earned = AchievementChecker.new(current_user).check_all!
      notice = newly_earned.any? ? "Workout added! You unlocked #{newly_earned.size} new achievement(s) 🏅" : "Workout added!"
      redirect_to workouts_path, notice: notice
    else
      redirect_to workouts_path, alert: workout.errors.full_messages.join(", ")
    end
  end

  private

  def workout_params
    params.require(:workout).permit(:sport, :distance_km_input, :distance_m_input, :duration_hours_input, :duration_minutes_input, :duration_seconds_input, :workout_date, :challenge_participation_id)
  end

  def update_participation_progress(workout)
    return unless workout.challenge_participation_id

    participation = workout.challenge_participation
    challenge = participation.challenge
    progress = challenge.target_unit == "km" ? participation.workouts.sum(:distance_km) : participation.workouts.sum(:duration_minutes).to_f / 60
    participation.update!(progress_value: progress)

    # Award badge if challenge completed
    if progress >= challenge.target_value.to_f && !participation.completed_at
      participation.update!(completed_at: Time.current)
      badge = Badge.find_or_create_by!(name: "Completed: #{challenge.title}") do |b|
        b.icon = "🏆"
        b.description = "Completed #{challenge.title}"
        b.badge_type = "challenge_completion"
      end
      unless participation.user.user_badges.exists?(badge: badge, challenge: challenge)
        participation.user.user_badges.create!(badge: badge, challenge: challenge, earned_at: Time.current)
      end
    end
  end
end
