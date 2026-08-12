class Workout < ApplicationRecord
  belongs_to :user
  belongs_to :challenge_participation, optional: true

  attr_accessor :distance_km_input, :distance_m_input, :duration_hours_input,
                :duration_minutes_input, :duration_seconds_input, :start_time_input

  before_validation :assign_distance_and_duration
  before_validation :assign_start_time
  after_create_commit :credit_season_progress

  scope :in_window, ->(window) { window ? where(workout_date: window_dates(window)) : none }

  # Only workouts whose clock time is trustworthy can satisfy hour-based
  # challenges — manual entries without a time must never qualify.
  scope :with_known_start_time, -> { where(start_time_known: true).where.not(started_at_local: nil) }

  def self.window_dates(window)
    return window unless window.begin.respond_to?(:to_date)

    window.begin.to_date..window.end.to_date
  end

  # Seconds per kilometre — lower is faster. Nil when it can't be computed.
  def pace_seconds_per_km
    seconds = moving_time_seconds.presence || (duration_minutes.to_i * 60)
    return nil if seconds.to_i.zero? || distance_km.to_f <= 0

    seconds / distance_km.to_f
  end

  # An activity finished "without stopping": the clock never diverged from the
  # moving time by more than a small tolerance.
  def uninterrupted?
    return false if elapsed_time_seconds.to_i.zero? || moving_time_seconds.to_i.zero?

    (elapsed_time_seconds - moving_time_seconds) <= [ (moving_time_seconds * 0.02).round, 30 ].max
  end

  def local_hour
    return nil unless start_minute_of_day

    start_minute_of_day / 60
  end

  # Wall-clock minutes since local midnight, derived without timezone conversion.
  def self.minute_of_day_from(time)
    return nil unless time

    utc = time.respond_to?(:utc) ? time.utc : time
    (utc.hour * 60) + utc.min
  end

  private

  # Every new workout enrolls the user in (and refreshes their progress for)
  # each active season — granting per-workout XP and re-evaluating objectives.
  def credit_season_progress
    active_seasons = Season.active.to_a
    return if active_seasons.empty?

    active_seasons.each do |season|
      SeasonProgressService.ensure_participation(user, season)
      SeasonRecalcJob.enqueue_debounced(user.id, season.id)
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
      total_seconds = (duration_hours_input.to_i * 3600) + (duration_minutes_input.to_i * 60) + duration_seconds_input.to_i
      self.duration_minutes = (total_seconds / 60.0).round
      self.moving_time_seconds ||= total_seconds
      self.elapsed_time_seconds ||= total_seconds
    end
  end

  # Manual entries may supply a start time; when they don't, we still stamp a
  # placeholder so ordering works, but flag it as unknown so hour-based
  # challenges skip the row.
  def assign_start_time
    if start_time_input.present? && workout_date.present?
      hour, minute = start_time_input.to_s.split(":")
      self.started_at_local = Time.utc(workout_date.year, workout_date.month, workout_date.day, hour.to_i, minute.to_i)
      self.started_at ||= started_at_local
      self.start_time_known = true
    elsif started_at_local.nil? && workout_date.present?
      self.started_at_local = workout_date.to_time(:utc) + 12.hours
      self.start_time_known = false
    end

    self.start_minute_of_day = self.class.minute_of_day_from(started_at_local)
  end
end
