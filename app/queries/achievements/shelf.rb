# frozen_string_literal: true

module Achievements
  # Achievements are season medals: one per season, earned with the fragments a
  # player collects from that season's challenges and objectives. Read by the
  # achievements page and GET /api/v1/achievements.
  class Shelf
    attr_reader :user

    def initialize(user)
      @user = user
    end

    def participations
      @participations ||= user.season_history.to_a
    end

    def medals
      @medals ||= participations.select(&:medal_tier)
    end

    # { "gold" => 2, "bronze" => 1 }
    def medal_counts
      @medal_counts ||= medals.group_by(&:medal_tier).transform_values(&:size)
    end

    def fragments
      participations.sum(&:medal_fragments)
    end

    def browsable_season_ids
      @browsable_season_ids ||= Season.browsable.pluck(:id).to_set
    end

    # Badges granted by season rewards — the extras a season hands out alongside
    # its medal. Challenge-completion badges stay on the challenge pages.
    def reward_badges
      @reward_badges ||= user.user_badges
                             .joins(:badge)
                             .merge(Badge.season)
                             .includes(:badge)
                             .order(earned_at: :desc)
                             .to_a
    end
  end
end
