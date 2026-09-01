# frozen_string_literal: true

# Announces a season out of band, so activating one in the admin panel returns
# immediately rather than waiting on push fan-out and a Slack round trip.
class AnnounceSeasonJob < ApplicationJob
  queue_as :default

  def perform(season_id, force: false)
    season = Season.find_by(id: season_id)
    return unless season

    SeasonAnnouncer.call(season, force: force)
  end
end
