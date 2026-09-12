# frozen_string_literal: true

# Achievements are season medals now: one medal per season, earned with the
# fragments a player collects from that season's challenges and objectives.
# There is no separate catalogue to grind — the seasons themselves are it.
class AchievementsController < ApplicationController
  before_action :authenticate_user!

  def index
    @participations = current_user.season_history.to_a
    @medals = @participations.select(&:medal_tier)
    @medal_counts = @medals.group_by(&:medal_tier).transform_values(&:size)
    @browsable_season_ids = Season.browsable.pluck(:id).to_set

    # Badges granted by season rewards — the extras a season hands out alongside
    # its medal. Challenge-completion badges stay on the challenge pages.
    @reward_badges = current_user.user_badges
                                 .joins(:badge)
                                 .merge(Badge.season)
                                 .includes(:badge)
                                 .order(earned_at: :desc)
  end
end
