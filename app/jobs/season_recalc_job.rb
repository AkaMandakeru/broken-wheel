# frozen_string_literal: true

class SeasonRecalcJob < ApplicationJob
  queue_as :default

  def perform(user_id, season_id)
    user = User.find_by(id: user_id)
    season = Season.find_by(id: season_id)
    return unless user && season

    participation = SeasonProgressService.ensure_participation(user, season)
    SeasonProgressService.new(participation).recalculate
  end
end
