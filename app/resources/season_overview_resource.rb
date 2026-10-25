# frozen_string_literal: true

# GET /api/v1/seasons/:id — the season header, the viewer's standing, the
# "new season" banner state and the next special event (a Seasons::Dashboard).
class SeasonOverviewResource < ApplicationResource
  attribute :season do |dashboard|
    SeasonResource.new(dashboard.season).serializable_hash.merge(
      level_curve: dashboard.season.level_curve_object.thresholds
    )
  end

  attribute :participation do |dashboard|
    dashboard.participation && SeasonParticipationResource.new(dashboard.participation).serializable_hash
  end

  # `visible` is whether the app should show the banner for this season now;
  # `dismissed` whether the player has closed it.
  attribute :announcement do |dashboard|
    next nil unless viewer

    {
      visible: Seasons::Announcement.for(viewer) == dashboard.season,
      dismissed: viewer.dismissed_season_announcement?(dashboard.season.id)
    }
  end

  attribute :next_special_event do |dashboard|
    event = dashboard.next_special_event
    event && SeasonChallengeResource.new(
      event, params: { progress: dashboard.challenge_progress, participation: dashboard.participation }
    ).serializable_hash
  end
end
