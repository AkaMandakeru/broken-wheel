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
      notice = if newly_earned.any?
                 t("flashes.workouts.added_with_achievements", count: newly_earned.size)
               else
                 t("flashes.workouts.added")
               end
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

    RecomputeChallengeProgress.new(workout.challenge_participation).call
  end
end
