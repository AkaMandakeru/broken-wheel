# frozen_string_literal: true

class SeasonRecalcJob < ApplicationJob
  queue_as :default

  # Collapses bursts (a 40-activity Strava import) into two runs per window:
  # one immediately so the UI updates, and one trailing run to pick up whatever
  # landed while the first was executing. Recalculation is idempotent, so the
  # extra pass is free of side effects.
  DEBOUNCE_WINDOW = 20.seconds

  def self.enqueue_debounced(user_id, season_id, window: DEBOUNCE_WINDOW)
    key = "season_recalc:#{user_id}:#{season_id}"
    return unless Rails.cache.write(key, true, expires_in: window, unless_exist: true)

    perform_later(user_id, season_id)
    set(wait: window).perform_later(user_id, season_id)
  end

  def perform(user_id, season_id)
    user = User.find_by(id: user_id)
    season = Season.find_by(id: season_id)
    return unless user && season

    participation = SeasonProgressService.ensure_participation(user, season)
    SeasonProgressService.new(participation).recalculate
  end
end
