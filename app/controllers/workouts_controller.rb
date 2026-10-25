# frozen_string_literal: true

class WorkoutsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_strava_connection, only: [ :strava_activities, :import_strava ]

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
    # A challenge can be live in more than one season, so a user may hold
    # several participations for it. The picker shows each challenge once.
    @participations = current_user.challenge_participations
                                  .joins(:challenge)
                                  .where(challenges: { status: "active" })
                                  .includes(:challenge)
                                  .order(Arel.sql("season_id IS NULL"))
                                  .to_a
                                  .uniq(&:challenge_id)
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

    imported = Strava::ManualImport.new(current_user, activity_ids).call

    notice = t("flashes.workouts.strava_imported", count: imported)
    # Back to the season, where the import actually shows up: new XP to claim,
    # challenge bars moved, dailies ticked off. `logged_in_home_path` walks past
    # seasons if the feature is switched off.
    redirect_to logged_in_home_path, notice: notice
  end

  def create
    workout = Workouts::ManualEntry.new(current_user, workout_params).call
    if workout.persisted?
      redirect_to workouts_path, notice: t("flashes.workouts.added")
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
end
