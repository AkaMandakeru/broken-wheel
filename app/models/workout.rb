class Workout < ApplicationRecord
  belongs_to :user
  belongs_to :challenge_participation, optional: true

  attr_accessor :distance_km_input, :distance_m_input, :duration_hours_input, :duration_minutes_input, :duration_seconds_input

  before_validation :assign_distance_and_duration
  after_create_commit :credit_season_progress

  private

  # Every new workout enrolls the user in (and refreshes their progress for)
  # each active season — granting per-workout XP and re-evaluating objectives.
  def credit_season_progress
    active_seasons = Season.active.to_a
    return if active_seasons.empty?

    active_seasons.each do |season|
      SeasonProgressService.ensure_participation(user, season)
      SeasonRecalcJob.perform_later(user.id, season.id)
    end

    notify_workout_xp(active_seasons.first)
  end

  def notify_workout_xp(season)
    PushNotifier.notify(
      user,
      title: I18n.t("push.workout_xp.title"),
      body: I18n.t("push.workout_xp.body", xp: SeasonProgressService::WORKOUT_XP),
      path: Rails.application.routes.url_helpers.season_path(season),
      tag: "season-xp" # collapses rapid notifications during a bulk import
    )
  end

  def assign_distance_and_duration
    if distance_km_input.present? || distance_m_input.present?
      self.distance_km = distance_km_input.to_f + (distance_m_input.to_f / 1000.0)
    end

    if duration_hours_input.present? || duration_minutes_input.present? || duration_seconds_input.present?
      self.duration_minutes = (duration_hours_input.to_i * 60) + duration_minutes_input.to_i + (duration_seconds_input.to_f / 60.0).round
    end
  end
end
