# frozen_string_literal: true

class WorkoutsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_strava_connection, only: [:strava_activities, :import_strava]

  rescue_from StravaService::Error do |e|
    Rails.logger.error("Strava error for user=#{current_user.id}: #{e.message}")
    redirect_to workouts_path, alert: t("flashes.workouts.strava_sync_failed")
  end

  rescue_from StravaService::RateLimitError do
    redirect_to workouts_path, alert: t("flashes.workouts.strava_rate_limited")
  end

  rescue_from StravaService::AuthError do
    redirect_to workouts_path, alert: t("flashes.workouts.strava_auth_failed")
  end

  def index
    @participations = current_user.challenge_participations.joins(:challenge).where(challenges: { status: "active" }).includes(:challenge)
    @workouts = current_user.workouts.order(workout_date: :desc).limit(20)
    @workout_count = current_user.workouts.count
    @unique_days = current_user.workouts.distinct.count(:workout_date)
    @strava_connected = current_user.connected_to_strava?
  end

  def strava_activities
    service = StravaService.new(current_user)
    @activities = service.activities(page_size: 50)
    @imported_ids = current_user.workouts
                                .where(provider: "strava")
                                .pluck(:external_id)
                                .to_set
  end

  def import_strava
    activity_ids = Array(params[:activity_ids]).map(&:to_s).reject(&:blank?)
    if activity_ids.empty?
      return redirect_to strava_activities_workouts_path, alert: t("flashes.workouts.no_activities_selected")
    end

    service = StravaService.new(current_user)
    importer = Strava::ActivityImporter.new(current_user, client: service)
    imported = 0

    activity_ids.each do |strava_id|
      activity = service.activity(strava_id)
      imported += 1 if importer.import_one(activity)
    end

    notice = t("flashes.workouts.strava_imported", count: imported)
    redirect_to workouts_path, notice: notice
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

  def require_strava_connection
    return if current_user.connected_to_strava?

    redirect_to workouts_path, alert: t("flashes.workouts.strava_not_connected")
  end

  def workout_params
    params.require(:workout).permit(:sport, :distance_km_input, :distance_m_input, :duration_hours_input, :duration_minutes_input, :duration_seconds_input, :workout_date, :challenge_participation_id)
  end

  def update_participation_progress(workout)
    return unless workout.challenge_participation_id

    RecomputeChallengeProgress.new(workout.challenge_participation).call
  end
end
