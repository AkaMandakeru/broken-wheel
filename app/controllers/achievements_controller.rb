# frozen_string_literal: true

# Achievements are season medals now: one medal per season, earned with the
# fragments a player collects from that season's challenges and objectives.
# There is no separate catalogue to grind — the seasons themselves are it.
class AchievementsController < ApplicationController
  before_action :authenticate_user!

  def index
    shelf = Achievements::Shelf.new(current_user)
    @participations = shelf.participations
    @medals = shelf.medals
    @medal_counts = shelf.medal_counts
    @browsable_season_ids = shelf.browsable_season_ids
    @reward_badges = shelf.reward_badges
  end
end
